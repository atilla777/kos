require "rails_helper"

RSpec.describe ActiveRecord::ConnectionAdapters::SQLite3Adapter do
  subject(:connection) { ActiveRecord::Base.connection }

  it "enables the required reliability pragmas" do
    pragmas = %w[journal_mode synchronous busy_timeout foreign_keys]

    expect(pragmas.to_h { |pragma| [ pragma, connection.select_value("PRAGMA #{pragma}") ] })
      .to eq("journal_mode" => "wal", "synchronous" => 2, "busy_timeout" => 5000, "foreign_keys" => 1)
  end
end
