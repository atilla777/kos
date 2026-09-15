require "rails_helper"

RSpec.describe Kos::JsonParser do
  it "parses JSON objects with unique member names" do
    expect(described_class.parse('{"value":1}')).to eq("value" => 1)
  end

  it "rejects duplicate member names at every object depth" do
    expect { described_class.parse('{"nested":{"value":1,"value":2}}') }
      .to raise_error(JSON::ParserError, /duplicate key "value"/)
  end

  it "rejects source bytes that are not valid UTF-8" do
    expect { described_class.parse("{\"value\":\"\xFF\"}".b) }
      .to raise_error(JSON::ParserError, /valid UTF-8/)
  end
end
