module WorkflowCatalog
  class DefinitionValidator
    INSTRUCTION_LIMIT = 128 * 1024
    TEMPLATE_LIMIT = 1024 * 1024
    STATE_CONTENT_LIMIT = 4 * 1024 * 1024
    ARTIFACT_CONDITIONS = %w[artifact-present artifact-state not-applicable].freeze

    def initialize(definition, task_type: nil, schema_registry: Kos::Cli::SchemaRegistry.new)
      @definition = definition
      @task_type = task_type
      @schema_registry = schema_registry
      @errors = []
    end

    def structural_errors
      add("/", "Definition does not satisfy the version 1 schema") unless schema_valid?
      if @task_type && @definition.is_a?(Hash)
        add("/workflow_id", "Workflow identity does not match the task type") if
          @definition["workflow_id"] != @task_type.workflow_id
        add("/task_type", "Task type does not match the workflow family") if
          @definition["task_type"] != @task_type.name
      end
      sorted_errors
    end

    def errors
      structural = structural_errors
      return structural unless structural.empty?

      validate_content
      validate_graph
      sorted_errors
    end

    private

    def schema_valid?
      @schema_registry.valid?("workflow_definition.json", "definition", @definition)
    end

    def validate_content
      @definition.fetch("statuses").each_with_index do |status, index|
        duplicate_values(status.fetch("artifact_templates").map { |template| template.fetch("id") }).each do |id|
          add("/statuses/#{index}/artifact_templates", "Duplicate artifact template identifier: #{id}")
        end
        duplicate_values(status.fetch("required_artifacts").map { |item| item.fetch("type") }).each do |type|
          add("/statuses/#{index}/required_artifacts", "Duplicate artifact requirement: #{type}")
        end
        contents = [ [ "instruction", status.fetch("instruction"), INSTRUCTION_LIMIT ] ]
        status.fetch("artifact_templates").each_with_index do |template, template_index|
          contents << [ "artifact_templates/#{template_index}/content", template.fetch("content"), TEMPLATE_LIMIT ]
        end
        contents.each do |field, content, limit|
          path = "/statuses/#{index}/#{field}"
          add(path, "Content must be valid UTF-8") unless content.encoding == Encoding::UTF_8 && content.valid_encoding?
          add(path, "Content exceeds the UTF-8 byte limit") if content.bytesize > limit
        end
        total = contents.sum { |_field, content, _limit| content.bytesize }
        add("/statuses/#{index}", "Instruction and templates exceed the state byte limit") if total > STATE_CONTENT_LIMIT
      end
    end

    def validate_graph
      statuses = @definition.fetch("statuses")
      transitions = @definition.fetch("transitions")
      status_ids = statuses.map { |status| status.fetch("id") }
      initial = @definition.fetch("initial_status")
      terminal = @definition.fetch("terminal_status")
      known_ids = status_ids + [ terminal ]

      duplicate_values(status_ids).each { |id| add("/statuses", "Duplicate status identifier: #{id}") }
      add("/initial_status", "Initial status must be executable") unless status_ids.include?(initial)
      add("/terminal_status", "Terminal status must be distinct from executable statuses") if status_ids.include?(terminal)

      transitions.each_with_index do |transition, index|
        add("/transitions/#{index}", "Transition endpoints must be distinct") if
          transition.fetch("from") == transition.fetch("to")
        %w[from to].each do |endpoint|
          add("/transitions/#{index}/#{endpoint}", "Transition endpoint is unknown") unless
            known_ids.include?(transition.fetch(endpoint))
        end
        add("/transitions/#{index}/from", "A transition cannot leave the terminal status") if
          transition.fetch("from") == terminal
      end

      duplicate_values(transitions.map { |transition| transition.values_at("from", "to") }).each do |from, to|
        add("/transitions", "Duplicate transition: #{from} -> #{to}")
      end
      status_ids.each do |id|
        add("/statuses/#{id}", "Executable status must have an outgoing transition") unless
          transitions.any? { |transition| transition.fetch("from") == id }
      end
      reachable = reachable_ids(initial, transitions)
      (known_ids.uniq - reachable).each { |id| add("/statuses/#{id}", "Status is unreachable from the initial status") }

      statuses.each_with_index do |status, index|
        validate_status_policy(status, index)
        validate_outgoing_contract(status, transitions)
      end
    end

    def validate_status_policy(status, index)
      if status.fetch("repository_changes") == "allowed" && status.fetch("worktree") != "required"
        add("/statuses/#{index}/worktree", "Repository changes require a worktree")
      end
      incompatible = status.fetch("allowed_repository_effects") & %w[commit rebase]
      if status.fetch("repository_changes") == "forbidden" && incompatible.any?
        add("/statuses/#{index}/allowed_repository_effects", "Repository effects conflict with change policy")
      end
      worktree_effects = status.fetch("allowed_repository_effects") & %w[worktree_remove commit rebase]
      if status.fetch("worktree") == "none" && worktree_effects.any?
        add("/statuses/#{index}/allowed_repository_effects", "Repository effects require a worktree")
      end
    end

    def validate_outgoing_contract(status, transitions)
      status_id = status.fetch("id")
      outgoing = transitions.each_with_index.select { |transition, _index| transition.fetch("from") == status_id }
      requirements = status.fetch("required_artifacts").to_h { |item| [ item.fetch("type"), item ] }
      decisions = []

      outgoing.each do |transition, index|
        conditions = transition.fetch("conditions")
        always = conditions.select { |condition| condition.fetch("type") == "always" }
        if always.any? && (conditions.length != 1 || requirements.any?)
          add("/transitions/#{index}/conditions", "Always must be the sole condition and requires no artifact output")
        end
        artifact_conditions = conditions.select { |condition| ARTIFACT_CONDITIONS.include?(condition.fetch("type")) }
        duplicate_values(artifact_conditions.map { |condition| condition.fetch("artifact_type") }).each do |type|
          add("/transitions/#{index}/conditions", "Duplicate artifact condition: #{type}")
        end
        edge_decisions = conditions.select { |condition| condition.fetch("type") == "decision" }
        duplicate_values(edge_decisions.map { |condition| condition.fetch("decision") }).each do |decision|
          add("/transitions/#{index}/conditions", "A decision has multiple values on one edge: #{decision}")
        end
        decisions.concat(edge_decisions.map { |condition| condition.values_at("decision", "value") })
        validate_edge_artifacts(index, requirements, artifact_conditions)
      end

      duplicate_values(decisions).each do |decision, value|
        add("/transitions", "Decision branch is ambiguous for #{decision}=#{value}")
      end
      validate_state_coverage(status_id, requirements, outgoing)
    end

    def validate_edge_artifacts(index, requirements, conditions)
      types = conditions.map { |condition| condition.fetch("artifact_type") }
      (requirements.keys - types).each do |type|
        add("/transitions/#{index}/conditions", "Required artifact lacks evidence or waiver: #{type}")
      end
      conditions.each do |condition|
        type = condition.fetch("artifact_type")
        requirement = requirements[type]
        unless requirement
          add("/transitions/#{index}/conditions", "Artifact condition is not declared by the source status: #{type}")
          next
        end
        if condition.fetch("type") == "artifact-state" &&
            !requirement.fetch("allowed_states").include?(condition.fetch("state"))
          add("/transitions/#{index}/conditions", "Artifact state is not allowed by the source status: #{type}")
        end
      end
    end

    def validate_state_coverage(status_id, requirements, outgoing)
      requirements.each_value do |requirement|
        routed = outgoing.flat_map do |transition, _index|
          conditions = transition.fetch("conditions").select do |condition|
            condition["artifact_type"] == requirement.fetch("type")
          end
          states = conditions.filter_map { |condition| condition["state"] if condition.fetch("type") == "artifact-state" }
          states.concat(requirement.fetch("allowed_states")) if
            conditions.any? { |condition| condition.fetch("type") == "artifact-present" }
          states
        end
        (requirement.fetch("allowed_states") - routed).each do |state|
          add("/statuses/#{status_id}/required_artifacts", "Artifact state has no evidence-bearing route: #{state}")
        end
      end
    end

    def reachable_ids(initial, transitions)
      reachable = [ initial ]
      loop do
        additions = transitions.filter_map do |transition|
          transition.fetch("to") if reachable.include?(transition.fetch("from"))
        end - reachable
        break if additions.empty?

        reachable.concat(additions)
      end
      reachable
    end

    def duplicate_values(values)
      values.group_by(&:itself).select { |_value, matches| matches.length > 1 }.keys
    end

    def add(field, message)
      @errors << { "field" => field, "message" => message }
    end

    def sorted_errors
      @errors.uniq.sort_by { |error| [ error.fetch("field"), error.fetch("message") ] }
    end
  end
end
