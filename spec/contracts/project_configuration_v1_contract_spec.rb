require "digest"
require "fileutils"
require "json"
require "json_schemer"
require "pathname"
require "psych"
require "set"
require "spec_helper"
require "tmpdir"

module ProjectConfigurationV1Contract
  SCHEMA_DIRECTORY = File.expand_path("../../schemas/project/v1", __dir__)
  FIXTURE_DIRECTORY = File.expand_path("../fixtures/project_configuration/v1", __dir__)
  VALID_DIRECTORY = File.join(FIXTURE_DIRECTORY, "valid")
  CANONICAL_MANIFEST_PATH = File.join(VALID_DIRECTORY, "bundle-manifest.canonical.json")
  SCHEMAS = Dir[File.join(SCHEMA_DIRECTORY, "*.json")].sort.to_h do |path|
    [ File.basename(path), JSON.parse(File.read(path)) ]
  end
  REGISTRY = SCHEMAS.values.to_h { |schema| [ URI(schema.fetch("$id")), schema ] }
  STANDARD_YAML_TAGS = %w[map seq str int float bool null].map { |name| "tag:yaml.org,2002:#{name}" }.freeze
  KNOWN_CAPABILITIES = %w[kos-development kos-review kos-publish].freeze
  GOLDEN_BUNDLE_DIGEST = "sha256:ccbf9783cdd0028dc72262cb693419eaa41e014c47eb62cb141297cd5f4f0404"

  class InvalidYaml < StandardError; end

  def self.references(value)
    case value
    when Hash
      value.flat_map { |key, child| (key == "$ref" ? [ child ] : []) + references(child) }
    when Array
      value.flat_map { |child| references(child) }
    else
      []
    end
  end

  def self.resolve_reference(root, reference)
    uri = URI.join(root.fetch("$id"), reference)
    document_uri = uri.dup
    document_uri.fragment = nil
    target = REGISTRY.fetch(document_uri)
    return target unless uri.fragment

    uri.fragment.delete_prefix("/").split("/").reduce(target) do |value, token|
      value.fetch(token.gsub("~1", "/").gsub("~0", "~"))
    end
  end

  def self.schema(name)
    JSONSchemer.schema(SCHEMAS.fetch(name), ref_resolver: REGISTRY.to_proc)
  end

  def self.condition_schema
    schema("workflow.json").ref("#/$defs/condition")
  end

  def self.condition_validity
    conditions = [ { "type" => "always" }, { "type" => "artifact-present", "artifact_type" => "candidate" },
      { "type" => "artifact-state", "artifact_type" => "test", "state" => "passed" },
      { "type" => "decision", "decision" => "delivery-path", "value" => "direct" },
      { "type" => "not-applicable", "artifact_type" => "document" }, { "type" => "expression", "code" => "true" } ]
    conditions.map { |condition| condition_schema.valid?(condition) }
  end

  def self.inspect_yaml_node(node)
    raise InvalidYaml, "aliases are forbidden" if node.is_a?(Psych::Nodes::Alias)
    if node.respond_to?(:tag) && node.tag && !STANDARD_YAML_TAGS.include?(node.tag)
      raise InvalidYaml, "custom tags are forbidden"
    end

    if node.is_a?(Psych::Nodes::Mapping)
      keys = node.children.each_slice(2).map(&:first).select { |key| key.is_a?(Psych::Nodes::Scalar) }.map(&:value)
      raise InvalidYaml, "duplicate keys are forbidden" unless keys.uniq.length == keys.length
    end
    node.children&.each { |child| inspect_yaml_node(child) } if node.respond_to?(:children)
  end

  def self.safe_yaml(path)
    source = File.binread(path)
    tree = Psych.parse_stream(source, filename: path)
    raise InvalidYaml, "exactly one YAML document is required" unless tree.children.one?

    inspect_yaml_node(tree)
    Psych.safe_load(source, permitted_classes: [], permitted_symbols: [], aliases: false, filename: path)
  rescue Psych::Exception => error
    raise InvalidYaml, error.message
  end

  def self.path_errors(root, path)
    pathname = Pathname(path)
    errors = []
    errors << "outside .kos" unless path.start_with?(".kos/")
    errors << "absolute" if pathname.absolute?
    errors << "traversal" if pathname.each_filename.any? { |part| %w[. ..].include?(part) }
    return errors unless errors.empty?

    current = Pathname(root)
    pathname.each_filename do |part|
      current = current.join(part)
      errors << "symlink" if current.symlink?
    end
    errors << "missing" unless current.file?
    errors
  end

  def self.workflow_members(workflow_path, workflow)
    referenced = workflow.fetch("statuses").flat_map do |status|
      [ status.fetch("instruction"), *status.fetch("materials").map { |material| material.fetch("path") } ]
    end
    sort_member_paths([ workflow_path, *referenced ].uniq)
  end

  def self.sort_member_paths(paths)
    paths.sort_by(&:b)
  end

  def self.manifest(root, workflow_path, workflow)
    members = workflow_members(workflow_path, workflow).map do |path|
      { "path" => path, "digest" => "sha256:#{Digest::SHA256.file(File.join(root, path)).hexdigest}" }
    end
    { "schema_version" => "1", "workflow_id" => workflow.fetch("id"),
      "workflow_version" => workflow.fetch("version"), "members" => members }
  end

  def self.canonical_json(value)
    case value
    when Hash
      "{#{value.keys.sort.map { |key| "#{JSON.generate(key)}:#{canonical_json(value.fetch(key))}" }.join(',')}}"
    when Array
      "[#{value.map { |item| canonical_json(item) }.join(',')}]"
    else
      JSON.generate(value)
    end
  end

  def self.bundle_digest(manifest)
    "sha256:#{Digest::SHA256.hexdigest(canonical_json(manifest))}"
  end

  def self.semantic_errors(workflow)
    statuses = workflow.fetch("statuses")
    transitions = workflow.fetch("transitions")
    status_ids = statuses.map { |status| status.fetch("id") }
    terminal = workflow.fetch("terminal_status")
    errors = []
    errors << "duplicate status" unless status_ids.uniq == status_ids
    errors << "invalid initial status" unless status_ids.include?(workflow.fetch("initial_status"))
    errors << "terminal is executable" if status_ids.include?(terminal)

    edges = transitions.map { |transition| transition.values_at("from", "to") }
    errors << "duplicate edge" unless edges.uniq == edges
    transitions.each do |transition|
      errors << "unknown source" unless status_ids.include?(transition.fetch("from"))
      errors << "unknown target" unless [ *status_ids, terminal ].include?(transition.fetch("to"))
      conditions = transition.fetch("conditions")
      errors << "always is not exclusive" if conditions.any? { |condition| condition.fetch("type") == "always" } && !conditions.one?
    end
    errors << "terminal has outgoing edge" if transitions.any? { |transition| transition.fetch("from") == terminal }
    errors << "status has no outgoing edge" unless status_ids.all? do |status_id|
      transitions.any? { |transition| transition.fetch("from") == status_id }
    end
    errors.concat(reachability_errors(workflow, status_ids, terminal))
    errors.concat(requirement_errors(statuses, transitions))
    errors.concat(decision_errors(transitions))
    errors.concat(member_reference_errors(statuses))
    errors
  end

  def self.reachability_errors(workflow, status_ids, terminal)
    reached = Set[workflow.fetch("initial_status")]
    loop do
      targets = workflow.fetch("transitions").filter_map do |transition|
        transition.fetch("to") if reached.include?(transition.fetch("from"))
      end
      break if targets.all? { |target| reached.include?(target) }

      reached.merge(targets)
    end
    reached == Set.new([ *status_ids, terminal ]) ? [] : [ "unreachable status" ]
  end

  def self.requirement_errors(statuses, transitions)
    statuses.flat_map do |status|
      requirements = status.fetch("required_artifacts")
      types = requirements.map { |requirement| requirement.fetch("type") }
      errors = []
      errors << "duplicate artifact requirement" unless types.uniq == types
      errors << "repository changes without worktree" if status.fetch("repository_changes") == "allowed" &&
        status.fetch("worktree") != "required"
      errors << "unknown capability" unless (status.fetch("allowed_capabilities") - KNOWN_CAPABILITIES).empty?
      outgoing = transitions.select { |transition| transition.fetch("from") == status.fetch("id") }
      errors.concat(outgoing.flat_map { |transition| edge_requirement_errors(requirements, transition.fetch("conditions")) })
      errors.concat(allowed_state_route_errors(requirements, outgoing))
      errors
    end
  end

  def self.edge_requirement_errors(requirements, conditions)
    return requirements.empty? ? [] : [ "always bypasses artifacts" ] if conditions.any? do |condition|
      condition.fetch("type") == "always"
    end

    errors = requirements.flat_map do |requirement|
      relevant = conditions.select do |condition|
        %w[artifact-present artifact-state not-applicable].include?(condition.fetch("type")) &&
          condition["artifact_type"] == requirement.fetch("type")
      end
      states = relevant.filter_map { |condition| condition["state"] }
      errors = []
      errors << "edge omits artifact requirement" if relevant.empty?
      errors << "artifact state mismatch" unless (states - requirement.fetch("allowed_states")).empty?
      errors
    end + conditions.filter_map do |condition|
      next if %w[always decision].include?(condition.fetch("type"))
      next if requirements.any? { |requirement| requirement.fetch("type") == condition.fetch("artifact_type") }

      "condition lacks artifact requirement"
    end
    artifact_types = conditions.filter_map do |condition|
      condition["artifact_type"] if %w[artifact-present artifact-state not-applicable].include?(condition.fetch("type"))
    end
    errors << "multiple artifact conditions for one type" unless artifact_types.uniq == artifact_types
    errors
  end

  def self.allowed_state_route_errors(requirements, transitions)
    conditions = transitions.flat_map { |transition| transition.fetch("conditions") }
    requirements.filter_map do |requirement|
      relevant = conditions.select { |condition| condition["artifact_type"] == requirement.fetch("type") }
      covered_states = relevant.any? { |condition| condition.fetch("type") == "artifact-present" } ?
        requirement.fetch("allowed_states") : relevant.filter_map { |condition| condition["state"] }
      "artifact states not covered" unless (requirement.fetch("allowed_states") - covered_states).empty?
    end
  end

  def self.member_reference_errors(statuses)
    statuses.flat_map do |status|
      instruction = status.fetch("instruction")
      materials = status.fetch("materials").map { |material| material.fetch("path") }
      errors = []
      errors << "duplicate material path" unless materials.uniq == materials
      errors << "instruction and material path collide" if materials.include?(instruction)
      errors
    end
  end

  def self.decision_errors(transitions)
    decisions = transitions.flat_map do |transition|
      transition.fetch("conditions").filter_map do |condition|
        next unless condition.fetch("type") == "decision"

        [ transition.fetch("from"), condition.fetch("decision"), condition.fetch("value") ]
      end
    end
    errors = []
    errors << "ambiguous decision" unless decisions.uniq == decisions
    conflicts = transitions.any? do |transition|
      grouped = transition.fetch("conditions").select { |condition| condition.fetch("type") == "decision" }
        .group_by { |condition| condition.fetch("decision") }
      grouped.any? { |_decision, conditions| conditions.map { |condition| condition.fetch("value") }.uniq.length > 1 }
    end
    errors << "conflicting decision values" if conflicts
    errors
  end

  def self.deep_copy(value)
    Marshal.load(Marshal.dump(value))
  end

  def self.valid_fixture
    task_type_path = File.join(VALID_DIRECTORY, ".kos/task-types/quick-fix.yaml")
    task_type = safe_yaml(task_type_path)
    workflow_path = task_type.dig("workflow", "path")
    workflow = safe_yaml(File.join(VALID_DIRECTORY, workflow_path))
    [ task_type, workflow_path, workflow ]
  end

  def self.pointer_errors(task_type)
    workflow = task_type.fetch("workflow")
    expected = ".kos/workflows/#{workflow.fetch('id')}/#{workflow.fetch('version')}/workflow.yaml"
    workflow.fetch("path") == expected ? [] : [ "workflow pointer path mismatch" ]
  end

  def self.member_content_errors(root, workflow)
    workflow.fetch("statuses").flat_map do |status|
      instruction = File.binread(File.join(root, status.fetch("instruction")))
      materials = status.fetch("materials").map { |material| File.binread(File.join(root, material.fetch("path"))) }
      errors = []
      errors << "instruction is empty" if instruction.empty?
      errors << "instruction is not UTF-8" unless instruction.dup.force_encoding(Encoding::UTF_8).valid_encoding?
      errors << "instruction exceeds 128 KiB" if instruction.bytesize > 131_072
      errors << "material is empty" if materials.any?(&:empty?)
      errors << "material is not UTF-8" if materials.any? { |bytes| !bytes.dup.force_encoding(Encoding::UTF_8).valid_encoding? }
      errors << "material exceeds 1 MiB" if materials.any? { |bytes| bytes.bytesize > 1_048_576 }
      errors << "status content exceeds 4 MiB" if instruction.bytesize + materials.sum(&:bytesize) > 4_194_304
      errors
    end
  end

  def self.schema_contract
    schemas = SCHEMAS.values
    references = schemas.flat_map { |schema| references(schema).map { |reference| [ schema, reference ] } }
    { valid: schemas.all? { |schema| JSONSchemer.valid_schema?(schema) },
      dialects: schemas.map { |schema| schema.fetch("$schema") }.uniq,
      unique_ids: schemas.map { |schema| schema.fetch("$id") }.uniq.length == schemas.length,
      local_refs: references.map(&:last).all? { |reference| reference.start_with?("#") || reference.match?(/\A[a-z-]+\.json#/) },
      resolvable: references.all? { |root, reference| resolve_reference(root, reference) } }
  end

  def self.valid_fixture_contract
    task_type, workflow_path, workflow = valid_fixture
    persisted = JSON.parse(File.read(File.join(VALID_DIRECTORY, "bundle-manifest.json")))
    { task_type_schema: schema("task-type.json").valid?(task_type), workflow_schema: schema("workflow.json").valid?(workflow),
      semantics: semantic_errors(workflow), safe_paths: workflow_members(workflow_path, workflow).all? do |path|
        path_errors(VALID_DIRECTORY, path).empty?
      end,
      pointer_identity: task_type.fetch("workflow").values_at("id", "version") == workflow.values_at("id", "version") &&
        pointer_errors(task_type).empty?,
      content: member_content_errors(VALID_DIRECTORY, workflow),
      manifest_schema: schema("bundle-manifest.json").valid?(persisted),
      manifest_complete: persisted == manifest(VALID_DIRECTORY, workflow_path, workflow) }
  end

  def self.invalid_path_contract
    invalid_paths = [ "/tmp/instruction.md", ".kos/../README.md", "docs/instruction.md", ".kos/missing.md" ]
    Dir.mktmpdir do |directory|
      FileUtils.cp_r("#{VALID_DIRECTORY}/.", directory)
      File.symlink("development.md", File.join(directory, ".kos/workflows/quick-fix/1.0.0/steps/link.md"))
      invalid_paths << ".kos/workflows/quick-fix/1.0.0/steps/link.md"
      invalid_paths.map { |path| path_errors(directory, path) }
    end
  end

  def self.graph_example(workflow, kind)
    deep_copy(workflow).tap do |value|
      case kind
      when :malformed then value["initial_status"] = "missing"
      when :unreachable then value.fetch("transitions").delete_at(0)
      when :duplicate_edge then value.fetch("transitions") << value.fetch("transitions").first
      when :terminal_outgoing
        value.fetch("transitions") << { "from" => "completed", "to" => "development", "conditions" => [ { "type" => "always" } ] }
      when :ambiguous_decision
        %w[review publication].each do |target|
          value.fetch("transitions") << { "from" => "implementation-planning", "to" => target,
            "conditions" => [ { "type" => "decision", "decision" => "delivery-path", "value" => "direct" } ] }
        end
      end
    end
  end

  def self.quick_fix_contract(workflow)
    statuses = workflow.fetch("statuses").to_h { |status| [ status.fetch("id"), status ] }
    { endpoints: workflow.values_at("initial_status", "terminal_status"), statuses: statuses.keys,
      execution: statuses.values.map { |status| status.values_at("execution_mode", "worktree") }.uniq,
      capabilities: statuses.transform_values { |status| status.fetch("allowed_capabilities") },
      changes: statuses.transform_values { |status| status.fetch("repository_changes") },
      planning_artifacts: statuses.fetch("implementation-planning").fetch("required_artifacts"),
      planning_conditions: workflow.fetch("transitions").first.fetch("conditions"),
      edges: workflow.fetch("transitions").map { |transition| transition.values_at("from", "to") } }
  end

  def self.digest_change_contract(workflow_path, workflow)
    original = manifest(VALID_DIRECTORY, workflow_path, workflow)
    reversed = deep_copy(workflow).tap do |value|
      value["statuses"] = value.fetch("statuses").reverse
      value.fetch("statuses").each { |status| status["materials"] = status.fetch("materials").reverse }
    end
    digest = bundle_digest(original)
    Dir.mktmpdir do |root|
      FileUtils.cp_r("#{VALID_DIRECTORY}/.", root)
      target = workflow.dig("statuses", 0, "materials", 0, "path")
      original_bytes = File.binread(File.join(root, target))
      File.binwrite(File.join(root, target), "#{original_bytes}\n")
      trailing_newline = bundle_digest(manifest(root, workflow_path, workflow)) != digest
      File.binwrite(File.join(root, target), original_bytes.gsub("\n", "\r\n"))
      crlf = bundle_digest(manifest(root, workflow_path, workflow)) != digest
      changed_path_workflow = deep_copy(workflow)
      changed_path = "#{target}.new"
      File.binwrite(File.join(root, changed_path), original_bytes)
      changed_path_workflow.dig("statuses", 0, "materials", 0)["path"] = changed_path
      path = bundle_digest(manifest(root, workflow_path, changed_path_workflow)) != digest
      changed_set_workflow = deep_copy(workflow)
      changed_set_workflow.dig("statuses", 0)["materials"] = []
      member_set = bundle_digest(manifest(root, workflow_path, changed_set_workflow)) != digest
      { trailing_newline: trailing_newline, crlf: crlf, path: path, member_set: member_set,
        order_independent: bundle_digest(manifest(VALID_DIRECTORY, workflow_path, reversed)) == digest }
    end
  end

  def self.unsafe_yaml_rejected?
    paths = %w[duplicate-key.yaml alias.yaml custom-tag.yaml multiple-documents.yaml]
      .map { |name| File.join(FIXTURE_DIRECTORY, "invalid", name) }
    paths.all? do |path|
      safe_yaml(path)
      false
    rescue InvalidYaml
      true
    end
  end

  def self.closed_schema_contract
    task_type, _workflow_path, workflow = valid_fixture
    task_type["extra"] = true
    workflow.fetch("statuses").first["extra"] = true
    unknown_condition = deep_copy(workflow)
    unknown_condition.fetch("transitions").first.fetch("conditions").first["type"] = "ruby"
    [ schema("task-type.json").valid?(task_type), schema("workflow.json").valid?(workflow),
      schema("workflow.json").valid?(unknown_condition) ]
  end

  def self.manifest_contract(workflow_path, workflow)
    generated = manifest(VALID_DIRECTORY, workflow_path, workflow)
    paths = generated.fetch("members").map { |member| member.fetch("path") }
    exact_hashes = generated.fetch("members").all? do |member|
      member.fetch("digest") == "sha256:#{Digest::SHA256.file(File.join(VALID_DIRECTORY, member.fetch('path'))).hexdigest}"
    end
    { sorted: paths == paths.sort_by(&:b), unique: paths.uniq == paths,
      complete: paths == workflow_members(workflow_path, workflow), exact_hashes: exact_hashes }
  end

  def self.invalid_output_contract(workflow)
    unknown_capability = deep_copy(workflow)
    unknown_capability.fetch("statuses").first.fetch("allowed_capabilities") << "kos-repository"
    incompatible = deep_copy(workflow)
    incompatible.dig("statuses", 1, "required_artifacts", 1)["subject"] = "task"
    bypassed = deep_copy(workflow)
    bypassed.fetch("transitions")[1]["conditions"] = [ { "type" => "always" } ]
    [ semantic_errors(unknown_capability).include?("unknown capability"), !schema("workflow.json").valid?(incompatible),
      semantic_errors(bypassed).include?("always bypasses artifacts") ]
  end

  def self.decision_only_bypass_errors(workflow)
    bypassed = deep_copy(workflow)
    bypassed.fetch("transitions") << { "from" => "development", "to" => "publication",
      "conditions" => [ { "type" => "decision", "decision" => "delivery-path", "value" => "direct" } ] }
    semantic_errors(bypassed)
  end

  def self.member_reference_validity(workflow)
    duplicate = deep_copy(workflow)
    duplicate.dig("statuses", 0, "materials") << deep_copy(duplicate.dig("statuses", 0, "materials", 0))
    collision = deep_copy(workflow)
    collision.dig("statuses", 0, "materials", 0)["path"] = collision.dig("statuses", 0, "instruction")
    [ duplicate, collision ].map { |value| semantic_errors(value) }
  end

  def self.conflicting_decision_errors(workflow)
    conflicting = deep_copy(workflow)
    conflicting.fetch("transitions").first.fetch("conditions").concat([
      { "type" => "decision", "decision" => "delivery-path", "value" => "direct" },
      { "type" => "decision", "decision" => "delivery-path", "value" => "decomposed" }
    ])
    semantic_errors(conflicting)
  end

  def self.contradictory_artifact_errors(workflow)
    contradictory = deep_copy(workflow)
    contradictory.fetch("transitions").first.fetch("conditions") <<
      { "type" => "not-applicable", "artifact_type" => "document" }
    semantic_errors(contradictory)
  end

  def self.quick_fix_contract_valid?(workflow)
    quick_fix_contract(workflow) == {
      endpoints: %w[implementation-planning completed], statuses: %w[implementation-planning development review publication],
      execution: [ %w[subagent required] ], capabilities: {
        "implementation-planning" => [], "development" => [ "kos-development" ],
        "review" => [ "kos-review" ], "publication" => [ "kos-publish" ]
      }, changes: { "implementation-planning" => "allowed", "development" => "allowed",
        "review" => "forbidden", "publication" => "forbidden" },
      planning_artifacts: [ { "type" => "document", "cardinality" => "one", "subject" => "task",
        "allowed_states" => [ "produced" ] } ],
      planning_conditions: [ { "type" => "artifact-state", "artifact_type" => "document", "state" => "produced" } ],
      edges: [ %w[implementation-planning development], %w[development review], %w[review development],
        %w[review publication], %w[publication completed] ]
    }
  end

  def self.manifest_membership_validity(workflow_path, workflow)
    expected = manifest(VALID_DIRECTORY, workflow_path, workflow)
    incomplete = deep_copy(expected).tap { |value| value.fetch("members").pop }
    extra = deep_copy(expected).tap do |value|
      value.fetch("members") << { "path" => ".kos/extra.md", "digest" => "sha256:#{'0' * 64}" }
    end
    [ expected, incomplete, extra ].map { |value| value.fetch("members") == expected.fetch("members") }
  end

  def self.member_content_case(case_name)
    _task_type, workflow_path, workflow = valid_fixture
    Dir.mktmpdir do |root|
      FileUtils.cp_r("#{VALID_DIRECTORY}/.", root)
      case case_name
      when :empty_instruction
        File.binwrite(File.join(root, workflow.dig("statuses", 0, "instruction")), "")
      when :empty_material
        File.binwrite(File.join(root, workflow.dig("statuses", 0, "materials", 0, "path")), "")
      when :invalid_instruction
        File.binwrite(File.join(root, workflow.dig("statuses", 0, "instruction")), "\xFF".b)
      when :invalid_material
        File.binwrite(File.join(root, workflow.dig("statuses", 0, "materials", 0, "path")), "\xFF".b)
      when :oversized_instruction
        File.binwrite(File.join(root, workflow.dig("statuses", 0, "instruction")), "a" * 131_073)
      when :oversized_material
        File.binwrite(File.join(root, workflow.dig("statuses", 0, "materials", 0, "path")), "a" * 1_048_577)
      when :oversized_total
        status = workflow.fetch("statuses").first
        status["materials"] = 4.times.map do |index|
          path = ".kos/workflows/quick-fix/1.0.0/materials/large-#{index}.md"
          File.binwrite(File.join(root, path), "a" * 1_048_576)
          { "path" => path, "media_type" => "text/markdown; charset=utf-8" }
        end
      end
      hashed = manifest(root, workflow_path, workflow).fetch("members").all? { |member| member.fetch("digest").start_with?("sha256:") }
      { hashed: hashed, errors: member_content_errors(root, workflow) }
    end
  end

  def self.media_reference_validity
    _task_type, _workflow_path, workflow = valid_fixture
    yaml_material = deep_copy(workflow)
    yaml_material.dig("statuses", 0, "materials", 0)["media_type"] = "application/yaml; charset=utf-8"
    bad_instruction = deep_copy(workflow)
    bad_instruction.fetch("statuses").first["instruction"] = ".kos/instruction.yaml"
    bad_material = deep_copy(workflow)
    bad_material.dig("statuses", 0, "materials", 0)["media_type"] = "text/plain"
    [ workflow, yaml_material, bad_instruction, bad_material ].map { |value| schema("workflow.json").valid?(value) }
  end

  def self.condition_semantics_validity
    _task_type, _workflow_path, workflow = valid_fixture
    decision = deep_copy(workflow)
    decision.fetch("transitions").first.fetch("conditions") <<
      { "type" => "decision", "decision" => "delivery-path", "value" => "direct" }
    not_applicable = deep_copy(workflow)
    not_applicable.fetch("transitions") << { "from" => "development", "to" => "publication", "conditions" => [
      { "type" => "artifact-state", "artifact_type" => "candidate", "state" => "produced" },
      { "type" => "not-applicable", "artifact_type" => "test" }
    ] }
    [ decision, not_applicable ].map { |value| schema("workflow.json").valid?(value) && semantic_errors(value).empty? }
  end

  def self.artifact_requirement_alignment
    cli_path = File.expand_path("../../schemas/cli/v1/workflow.json", __dir__)
    cli_schema = JSONSchemer.schema(JSON.parse(File.read(cli_path))).ref("#/$defs/required_artifact")
    project_schema = schema("common.json").ref("#/$defs/artifact_requirement")
    _task_type, _workflow_path, workflow = valid_fixture
    requirements = workflow.fetch("statuses").flat_map { |status| status.fetch("required_artifacts") }
    requirements.all? { |requirement| project_schema.valid?(requirement) && cli_schema.valid?(requirement) }
  end

  def self.member_annotations
    definitions = SCHEMAS.fetch("workflow.json").fetch("$defs")
    { instruction_media_type: definitions.dig("status", "properties", "instruction", "x-media-type"),
      instruction_min_bytes: definitions.dig("status", "properties", "instruction", "x-min-utf8-bytes"),
      instruction_bytes: definitions.dig("status", "properties", "instruction", "x-max-utf8-bytes"),
      material_media_types: definitions.dig("material", "properties", "media_type", "enum"),
      material_min_bytes: definitions.dig("material", "x-min-utf8-bytes"),
      material_bytes: definitions.dig("material", "x-max-utf8-bytes"),
      total_bytes: SCHEMAS.fetch("workflow.json").fetch("x-max-total-member-content-bytes") }
  end

  def self.member_annotations_valid?
    member_annotations == { instruction_media_type: "text/markdown; charset=utf-8", instruction_min_bytes: 1,
      instruction_bytes: 131_072,
      material_media_types: [ "text/markdown; charset=utf-8", "application/yaml; charset=utf-8" ],
      material_min_bytes: 1, material_bytes: 1_048_576, total_bytes: 4_194_304 }
  end

  def self.canonical_fixture_contract
    manifest = JSON.parse(File.read(File.join(VALID_DIRECTORY, "bundle-manifest.json")))
    bytes = File.binread(CANONICAL_MANIFEST_PATH)
    members = manifest.fetch("members").map { |member| member.fetch("path") }
    { exact_bytes: canonical_json(manifest) == bytes,
      digest: "sha256:#{Digest::SHA256.hexdigest(bytes)}",
      excluded: members.none? { |path| path.end_with?(File.basename(CANONICAL_MANIFEST_PATH)) } }
  end

  def self.utf8_path_sort_vector
    paths = [ ".kos/\u00E4.md", ".kos/\u03B1.md", ".kos/z.md", ".kos/aa.md" ]
    sort_member_paths(paths)
  end
end

RSpec.describe ProjectConfigurationV1Contract do
  it "validates every schema against draft 2020-12 and resolves every reference locally" do
    expect(described_class.schema_contract).to eq(valid: true,
      dialects: [ "https://json-schema.org/draft/2020-12/schema" ], unique_ids: true, local_refs: true, resolvable: true)
  end

  it "accepts the complete quick-fix task type, workflow, and generated manifest" do
    expect(described_class.valid_fixture_contract).to eq(task_type_schema: true, workflow_schema: true,
      semantics: [], safe_paths: true, pointer_identity: true, content: [], manifest_schema: true, manifest_complete: true)
  end

  it "rejects duplicate keys, aliases, custom YAML tags, and multiple YAML documents before safe loading" do
    expect(described_class.unsafe_yaml_rejected?).to be(true)
  end

  it "uses closed schemas and rejects unknown fields and unknown conditions" do
    expect(described_class.closed_schema_contract).to eq([ false, false, false ])
  end

  it "accepts exactly the five typed transition condition forms" do
    expect(described_class.condition_validity).to eq([ true, true, true, true, true, false ])
  end

  it "applies coherent generic decision and artifact waiver semantics" do
    expect(described_class.condition_semantics_validity).to eq([ true, true ])
  end

  it "requires Markdown instructions and explicit closed material media types" do
    expect(described_class.media_reference_validity).to eq([ true, true, false, false ])
  end

  it "publishes the CLI-aligned member media and byte constraints" do
    expect(described_class.member_annotations_valid?).to be(true)
  end

  it "keeps project and CLI required artifact contracts aligned" do
    expect(described_class.artifact_requirement_alignment).to be(true)
  end

  it "rejects absolute, traversing, outside-.kos, missing, and symlink references" do
    expect(described_class.invalid_path_contract).to eq([
      [ "outside .kos", "absolute" ], [ "traversal" ], [ "outside .kos" ], [ "missing" ], [ "symlink" ]
    ])
  end

  it "rejects a task-type pointer path that does not match workflow identity and version" do
    task_type, = described_class.valid_fixture
    task_type.fetch("workflow")["path"] = ".kos/workflows/other/1.0.0/workflow.yaml"
    expect(described_class.pointer_errors(task_type)).to eq([ "workflow pointer path mismatch" ])
  end

  it "requires the complete direct reference closure with exact byte hashes and sorted unique paths" do
    _task_type, workflow_path, workflow = described_class.valid_fixture
    expect(described_class.manifest_contract(workflow_path, workflow))
      .to eq(sorted: true, unique: true, complete: true, exact_hashes: true)
  end

  it "rejects incomplete and extra manifest member sets independently" do
    _task_type, workflow_path, workflow = described_class.valid_fixture
    expect(described_class.manifest_membership_validity(workflow_path, workflow)).to eq([ true, false, false ])
  end

  it "rejects the old unprefixed sha256 manifest member shape" do
    manifest = JSON.parse(File.read(File.join(described_class::VALID_DIRECTORY, "bundle-manifest.json")))
    old_member = manifest.fetch("members").first.except("digest").merge("sha256" => "0" * 64)
    manifest.fetch("members")[0] = old_member
    expect(described_class.schema("bundle-manifest.json")).not_to be_valid(manifest)
  end

  { "a malformed initial status" => [ :malformed, "invalid initial status" ],
    "an unreachable status" => [ :unreachable, "unreachable status" ],
    "a duplicate edge" => [ :duplicate_edge, "duplicate edge" ],
    "an outgoing terminal edge" => [ :terminal_outgoing, "terminal has outgoing edge" ],
    "an ambiguous generic decision branch" => [ :ambiguous_decision, "ambiguous decision" ] }.each do |name, (kind, error)|
    it "rejects #{name}" do
      _task_type, _workflow_path, workflow = described_class.valid_fixture
      expect(described_class.semantic_errors(described_class.graph_example(workflow, kind))).to include(error)
    end
  end

  it "rejects an unknown workflow capability" do
    _task_type, _workflow_path, workflow = described_class.valid_fixture
    expect(described_class.invalid_output_contract(workflow).first).to be(true)
  end

  it "rejects an incompatible artifact type and subject contract" do
    _task_type, _workflow_path, workflow = described_class.valid_fixture
    expect(described_class.invalid_output_contract(workflow)[1]).to be(true)
  end

  it "rejects a transition that bypasses required artifact output" do
    _task_type, _workflow_path, workflow = described_class.valid_fixture
    expect(described_class.invalid_output_contract(workflow).last).to be(true)
  end

  it "rejects a decision-only development edge despite evidence on another outgoing edge" do
    _task_type, _workflow_path, workflow = described_class.valid_fixture
    expect(described_class.decision_only_bypass_errors(workflow)).to include("edge omits artifact requirement")
  end

  it "rejects two values for one decision on the same transition" do
    _task_type, _workflow_path, workflow = described_class.valid_fixture
    expect(described_class.conflicting_decision_errors(workflow)).to include("conflicting decision values")
  end

  it "rejects not-applicable combined with artifact evidence for one type on an edge" do
    _task_type, _workflow_path, workflow = described_class.valid_fixture
    expect(described_class.contradictory_artifact_errors(workflow)).to include("multiple artifact conditions for one type")
  end

  it "rejects duplicate material paths within one status" do
    _task_type, _workflow_path, workflow = described_class.valid_fixture
    expect(described_class.member_reference_validity(workflow).first).to include("duplicate material path")
  end

  it "rejects an instruction and material path collision within one status" do
    _task_type, _workflow_path, workflow = described_class.valid_fixture
    expect(described_class.member_reference_validity(workflow).last).to include("instruction and material path collide")
  end

  it "pins the representative quick-fix execution and transition semantics" do
    _task_type, _workflow_path, workflow = described_class.valid_fixture
    expect(described_class.quick_fix_contract_valid?(workflow)).to be(true)
  end

  it "pins the canonical manifest golden digest without a self-digest field" do
    manifest = JSON.parse(File.read(File.join(described_class::VALID_DIRECTORY, "bundle-manifest.json")))

    expect([ manifest.key?("bundle_digest"), described_class.bundle_digest(manifest) ])
      .to eq([ false, described_class::GOLDEN_BUNDLE_DIGEST ])
  end

  it "matches and hashes the independent compact canonical manifest byte fixture" do
    expect(described_class.canonical_fixture_contract).to eq(
      exact_bytes: true, digest: described_class::GOLDEN_BUNDLE_DIGEST, excluded: true
    )
  end

  it "changes the digest for member bytes, paths, and member sets but not input enumeration order" do
    _task_type, workflow_path, workflow = described_class.valid_fixture
    expect(described_class.digest_change_contract(workflow_path, workflow))
      .to eq(trailing_newline: true, crlf: true, path: true, member_set: true, order_independent: true)
  end

  it "sorts member paths lexicographically by UTF-8 bytes" do
    expect(described_class.utf8_path_sort_vector).to eq([
      ".kos/aa.md", ".kos/z.md", ".kos/\u00E4.md", ".kos/\u03B1.md"
    ])
  end

  { "an empty instruction" => [ :empty_instruction, "instruction is empty" ],
    "an empty material" => [ :empty_material, "material is empty" ],
    "non-UTF-8 instruction bytes" => [ :invalid_instruction, "instruction is not UTF-8" ],
    "non-UTF-8 material bytes" => [ :invalid_material, "material is not UTF-8" ],
    "an instruction over 128 KiB" => [ :oversized_instruction, "instruction exceeds 128 KiB" ],
    "a material over 1 MiB" => [ :oversized_material, "material exceeds 1 MiB" ],
    "status content over 4 MiB" => [ :oversized_total, "status content exceeds 4 MiB" ] }.each do |name, (kind, error)|
    it "hashes exact bytes before rejecting #{name}" do
      result = described_class.member_content_case(kind)
      expect(result.fetch(:hashed) && result.fetch(:errors).include?(error)).to be(true)
    end
  end
end
