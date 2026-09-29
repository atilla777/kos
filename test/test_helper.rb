ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    def workflow_for(project)
      project.workflows.first || project.workflows.create!(name: "Test workflow", steps: [
        { "name" => "Work", "instructions" => "Perform the test task.", "executor" => "main",
          "inputs" => [], "outputs" => [] }
      ])
    end

    # Add more helper methods to be used by all tests here...
  end
end
