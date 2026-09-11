require "rails_helper"

RSpec.describe WorkflowCatalog::CanonicalJson, :aggregate_failures do
  let(:appendix_b_vectors) do
    {
      "0000000000000000" => "0", "8000000000000000" => "0", "0000000000000001" => "5e-324",
      "8000000000000001" => "-5e-324", "7fefffffffffffff" => "1.7976931348623157e+308",
      "ffefffffffffffff" => "-1.7976931348623157e+308", "4340000000000000" => "9007199254740992",
      "c340000000000000" => "-9007199254740992", "4430000000000000" => "295147905179352830000",
      "44b52d02c7e14af5" => "9.999999999999997e+22", "44b52d02c7e14af6" => "1e+23",
      "44b52d02c7e14af7" => "1.0000000000000001e+23", "444b1ae4d6e2ef4e" => "999999999999999700000",
      "444b1ae4d6e2ef4f" => "999999999999999900000", "444b1ae4d6e2ef50" => "1e+21",
      "3eb0c6f7a0b5ed8c" => "9.999999999999997e-7", "3eb0c6f7a0b5ed8d" => "0.000001",
      "41b3de4355555553" => "333333333.3333332", "41b3de4355555554" => "333333333.33333325",
      "41b3de4355555555" => "333333333.3333333", "41b3de4355555556" => "333333333.3333334",
      "41b3de4355555557" => "333333333.33333343", "becbf647612f3696" => "-0.0000033333333333333333",
      "43143ff3c1cb0959" => "1424953923781206.2"
    }
  end

  it "matches the RFC 8785 primitive and number vector" do
    input = { "numbers" => [ 333333333.33333329, 1E30, 4.50, 2e-3, 1e-27 ],
      "string" => "\u20ac$\u000F\nA'B\"\\\"/", "literals" => [ nil, true, false ] }
    expected = "{\"literals\":[null,true,false],\"numbers\":[333333333.3333333,1e+30,4.5,0.002,1e-27]," \
      "\"string\":\"€$\\u000f\\nA'B\\\"\\\\\\\"/\"}"

    expect(described_class.generate(input)).to eq(expected)
  end

  it "sorts object keys by their UTF-16 code units" do
    input = { "€" => "Euro", "\r" => "Return", "\n" => "Newline", "1" => "One", "" => "Control",
      "😂" => "Smiley", "ö" => "Latin", "דּ" => "Hebrew", "</script>" => "Browser" }

    expect(JSON.parse(described_class.generate(input)).keys)
      .to eq([ "\n", "\r", "1", "</script>", "", "ö", "€", "😂", "דּ" ])
  end

  it "rejects non-finite numbers and invalid UTF-8" do
    invalid = "invalid".dup.force_encoding(Encoding::UTF_8)
    invalid.setbyte(0, 0xFF)

    expect { described_class.generate([ Float::NAN, invalid ]) }.to raise_error(RangeError)
    expect { described_class.generate(invalid) }.to raise_error(EncodingError)
  end

  it "serializes the RFC 8785 Appendix B IEEE 754 vectors" do
    actual = appendix_b_vectors.to_h { |hex, _expected| [ hex, described_class.generate([ hex ].pack("H*").unpack1("G")) ] }
    expect(actual).to eq(appendix_b_vectors)
  end

  it "uses ECMAScript number conversion for large parsed integers" do
    expect(described_class.generate([ 1.0, 9_007_199_254_740_992, 295_147_905_179_352_830_000 ]))
      .to eq("[1,9007199254740992,295147905179352830000]")
  end
end
