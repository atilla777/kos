# Run using bin/ci

CI.run do
  step "Setup", "env RAILS_ENV=test bin/setup --skip-server"

  step "Style: Ruby", "bin/rubocop"

  step "Security: Gem audit", "bin/bundler-audit"
  step "Security: Brakeman code analysis", "bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error"
  step "Tests: Rails", "bin/rails test"
  step "Tests: CLI", "ruby -Icli/lib:cli/test cli/test/repository_test.rb && ruby -Icli/lib:cli/test cli/test/command_test.rb && ruby -Icli/lib:cli/test cli/test/client_test.rb"
  step "Tests: OpenCode installation", "ruby script/test_install_opencode.rb"
  step "Build: CLI gem", "cd cli && gem build kos-cli.gemspec --output /tmp/kos-cli.gem"
  step "Acceptance: installed CLI and backup", "script/acceptance"
  step "Tests: Seeds", "env RAILS_ENV=test bin/rails db:seed:replant"

  # Optional: Run system tests
  # step "Tests: System", "bin/rails test:system"

  # Optional: set a green GitHub commit status to unblock PR merge.
  # Requires the `gh` CLI and `gh extension install basecamp/gh-signoff`.
  # if success?
  #   step "Signoff: All systems go. Ready for merge and deploy.", "gh signoff"
  # else
  #   failure "Signoff: CI failed. Do not merge or deploy.", "Fix the issues and try again."
  # end
end
