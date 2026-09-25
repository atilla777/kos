require "digest"
require "json"

root = File.expand_path(__dir__)
evidence_json = File.binread(File.join(root, "sentinel-runs.json"))
abort "sensitive metadata key retained" if evidence_json.match?(/"[^\"]*(?:session|credential|token|home|path)[^\"]*"\s*:/i)
evidence = JSON.parse(evidence_json)
template = File.binread(File.join(root, evidence.fetch("template_file")))
expected_cases = {
  "quoted-multiword-argv" => {
    "shell_command" => 'opencode run --format json --command argument-sentinel "ORDINARY MULTIWORD 015"',
    "message_argv" => [ "ORDINARY MULTIWORD 015" ],
    "relation" => "display-serialized-single-argv",
    "expanded" => '"ORDINARY MULTIWORD 015"'
  },
  "separate-multiword-argv" => {
    "shell_command" => "opencode run --format json --command argument-sentinel ORDINARY MULTIWORD 015",
    "message_argv" => [ "ORDINARY", "MULTIWORD", "015" ],
    "relation" => "plain-space-joined-argv",
    "expanded" => "ORDINARY MULTIWORD 015"
  },
  "literal-quotes-in-quoted-argv" => {
    "shell_command" => %q(opencode run --format json --command argument-sentinel 'display literal "ready" 015'),
    "message_argv" => [ 'display literal "ready" 015' ],
    "relation" => "display-serialized-single-argv-with-escaped-quotes",
    "expanded" => '"display literal \"ready\" 015"'
  },
  "boundary-whitespace-newlines" => {
    "shell_command" => %q(opencode run --format json --command argument-sentinel $'\n BOUNDARY_WHITESPACE_015 \n'),
    "message_argv" => [ "\n BOUNDARY_WHITESPACE_015 \n" ],
    "relation" => "display-serialized-single-argv",
    "expanded" => "\"\n BOUNDARY_WHITESPACE_015 \n\""
  }
}

abort "unexpected OpenCode version" unless evidence.fetch("opencode_version") == "1.18.26"
abort "template digest mismatch" unless Digest::SHA256.hexdigest(template) == evidence.fetch("template_sha256")
abort "unexpected case count" unless evidence.fetch("cases").length == expected_cases.length

evidence.fetch("cases").each do |test_case|
  expected_case = expected_cases.fetch(test_case.fetch("name"))
  abort "shell command mismatch" unless test_case.fetch("shell_command") == expected_case.fetch("shell_command")
  abort "expansion relation mismatch" unless test_case.fetch("expansion_relation") == expected_case.fetch("relation")
  argv = test_case.fetch("argv")
  abort "unexpected command argv" unless argv.first(6) ==
    [ "opencode", "run", "--format", "json", "--command", "argument-sentinel" ]
  message_argv = argv.drop(6)
  abort "message argv mismatch" unless message_argv == expected_case.fetch("message_argv")
  abort "message argv hex mismatch" unless message_argv.map { |value| value.b.unpack1("H*") } ==
    test_case.fetch("message_argv_hex")

  expected = expected_case.fetch("expanded").b
  abort "expanded bytes mismatch" unless test_case.fetch("expected_expanded_hex") == expected.unpack1("H*")
  joined_argv = message_argv.join(" ").b
  case test_case.fetch("expansion_relation")
  when "plain-space-joined-argv"
    abort "separate argv words were not preserved plainly" unless message_argv.length > 1 && expected == joined_argv
  when "display-serialized-single-argv"
    abort "single argv distinction missing" unless message_argv.one? && expected != joined_argv &&
      expected.start_with?('"') && expected.end_with?('"')
  when "display-serialized-single-argv-with-escaped-quotes"
    abort "literal quote distinction missing" unless message_argv.one? && joined_argv.include?('"') &&
      expected != joined_argv && expected.include?('\\"')
  else
    abort "unknown expansion relation"
  end

  runs = test_case.fetch("runs")
  abort "expected two independent runs" unless runs.map { |run| run.fetch("run") } == [ 1, 2 ]
  expanded = runs.map do |run|
    bytes = [ run.fetch("expanded_hex") ].pack("H*")
    abort "run expansion mismatch" unless bytes == expected
    abort "byte length mismatch" unless bytes.bytesize == run.fetch("bytes")
    abort "digest mismatch" unless Digest::SHA256.hexdigest(bytes) == run.fetch("sha256")
    bytes
  end
  abort "independent runs differ" unless expanded[0] == expanded[1]
end

puts "verified 4 argv/expansion cases, 8 runs, and 4 byte-identical pairs"
