require "test_helper"
require "open3"
require "rbconfig"
require "tmpdir"

class GemPackageTest < ActiveSupport::TestCase
  test "builds and installs a standalone kos executable" do
    Dir.mktmpdir("kos-gem") do |directory|
      root = Pathname(directory)
      package = root.join("kos.gem")
      gem_home = root.join("gem-home")
      bin_dir = root.join("bin")

      _output, error, status = Open3.capture3(RbConfig.ruby, "-S", "gem", "build", "kos.gemspec",
        "--output", package.to_s, chdir: Rails.root.to_s)
      assert_predicate status, :success?, error

      _output, error, status = Open3.capture3(RbConfig.ruby, "-S", "gem", "install", package.to_s,
        "--install-dir", gem_home.to_s, "--bindir", bin_dir.to_s, "--no-document")
      assert_predicate status, :success?, error

      environment = {
        "BUNDLE_GEMFILE" => nil, "GEM_HOME" => gem_home.to_s, "GEM_PATH" => gem_home.to_s,
        "RUBYGEMS_GEMDEPS" => nil, "RUBYOPT" => nil, "RUBYLIB" => nil
      }
      output, error, status = Open3.capture3(environment, bin_dir.join("kos").to_s, "--version", chdir: directory)

      assert_predicate status, :success?, error
      assert_equal "kos #{Kos::VERSION}\n", output
      assert_empty error

      output, error, status = Open3.capture3(environment, bin_dir.join("kos").to_s, "--help", chdir: directory)
      assert_predicate status, :success?, error
      assert_includes output, "KOS task coordination CLI"
    end
  end
end
