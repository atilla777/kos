require "active_record"
require "json"

database, scenario = ARGV
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database:)
connection = ActiveRecord::Base.connection
connection.create_table(:tasks) { |table| table.string :owner_id }

owners = case scenario
when "valid" then [ "session-1", "session-2", nil ]
when "duplicate" then [ "session", "session" ]
when "blank" then [ " " ]
end
owners.each { |owner| connection.execute("INSERT INTO tasks (owner_id) VALUES (#{connection.quote(owner)})") }

require_relative "../../db/migrate/20260921010000_enforce_unique_task_owner"

error = nil
begin
  EnforceUniqueTaskOwner.new.migrate(:up)
rescue StandardError => exception
  error = exception.message
end

puts JSON.generate(
  error:,
  owner_indexes: connection.indexes(:tasks).count do |index|
    index.columns == [ "owner_id" ] && index.unique && index.where == "owner_id IS NOT NULL"
  end
)
