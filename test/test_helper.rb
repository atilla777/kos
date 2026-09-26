ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "support/git_repository_helpers"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    def valid_workflow_definition
      {
        "steps" => [
          {
            "id" => "develop",
            "name" => "Develop",
            "execution_mode" => "main",
            "model_tier" => "advanced",
            "instruction" => "Implement the task.",
            "artifact_template" => "# Development",
            "outcomes" => {
              "ready" => { "next_step" => "check" },
              "question" => { "pause" => "needs_human" }
            }
          },
          {
            "id" => "check",
            "name" => "Check",
            "execution_mode" => "subagent",
            "model_tier" => "standard",
            "instruction" => "Run the checks.",
            "artifact_template" => "# Checks",
            "outcomes" => {
              "passed" => { "complete_task" => true },
              "failed" => { "next_step" => "develop" },
              "blocked" => { "pause" => "blocked" }
            }
          }
        ]
      }
    end

    def acceptance_workflow_definition
      BuiltInCatalog.definitions.fetch("development").deep_dup
    end

    def create_project(name: "Project", remote_url: nil)
      remote_url ||= "https://example.test/test/#{name.parameterize}-#{SecureRandom.hex(6)}.git"
      Project.create!(name:, remote_url:, repository_identity: RepositoryIdentity.normalize(remote_url),
        default_branch: "main")
    end

    def create_workflow(name: "Workflow", definition: valid_workflow_definition)
      Workflow.create!(name:, definition_json: definition)
    end

    def create_task_type(name: "Type", key: nil, workflow: nil)
      workflow ||= create_workflow
      key ||= "custom-test-#{SecureRandom.hex(8)}"
      TaskType.create!(key:, name:, workflow:)
    end

    def create_task(project: nil, workflow: nil, task_type: nil, parent: nil, current_step: "develop", title: "Task")
      project ||= create_project
      workflow ||= create_workflow
      task_type ||= create_task_type(workflow:)

      Task.create!(project:, task_type:, workflow:, parent:, title:,
        description_markdown: "Description", current_step:)
    end
  end
end
