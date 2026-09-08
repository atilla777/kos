ENV["RAILS_ENV"] ||= "test"

require_relative "../config/environment"
require "rspec/rails"
require "spec_helper"

abort("The Rails environment is running in production mode!") if Rails.env.production?

ActiveRecord::Migration.maintain_test_schema!

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.filter_rails_from_backtrace!
end
