require_relative "lib/kos_cli/version"

Gem::Specification.new do |spec|
  spec.name = "kos-cli"
  spec.version = KosCli::VERSION
  spec.summary = "Command-line client for the local KOS task tracker"
  spec.authors = [ "KOS contributors" ]
  spec.files = Dir["exe/*", "lib/**/*.rb", "README.md", "LICENSE"]
  spec.homepage = "https://github.com/atilla777/kos"
  spec.bindir = "exe"
  spec.executables = [ "kos" ]
  spec.require_paths = [ "lib" ]
  spec.required_ruby_version = ">= 3.4.0"
  spec.license = "MIT"
end
