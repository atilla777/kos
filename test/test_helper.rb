ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

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

    def create_project(name: "Project")
      Project.create!(name:, remote_url: "https://example.test/#{name.parameterize}.git", default_branch: "main")
    end

    def create_workflow(name: "Workflow", definition: valid_workflow_definition)
      Workflow.create!(name:, definition_json: definition)
    end

    def create_task(project: nil, workflow: nil, task_type: nil, parent: nil, current_step: "develop", title: "Task")
      project ||= create_project
      workflow ||= create_workflow
      task_type ||= TaskType.create!(name: "Type", workflow:)

      Task.create!(project:, task_type:, workflow:, parent:, title:,
        description_markdown: "Description", current_step:)
    end
  end
end
