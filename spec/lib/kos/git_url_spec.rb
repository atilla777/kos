require "spec_helper"
require_relative "../../../lib/kos/git_url"

RSpec.describe Kos::GitUrl, :aggregate_failures do
  it "normalizes scp-like Git URLs to SSH URIs" do
    expect(described_class.normalize("git@Example.COM:team/project.git"))
      .to eq("ssh://git@example.com/team/project.git")
  end

  it "normalizes URI scheme and host casing" do
    expect(described_class.normalize("SSH://git@Example.COM/team/project.git"))
      .to eq("ssh://git@example.com/team/project.git")
  end

  it "accepts the supported credential-free URL forms" do
    urls = [ "https://example.test/team/project.git", "git://example.test/team/project.git",
      "file:///srv/git/project.git" ]

    expect(urls.map { |url| described_class.normalize(url) }).to eq(urls)
  end

  it "rejects credentials, unsupported schemes, queries, and fragments" do
    urls = [ "https://user@example.test/project.git", "ssh://user:secret@example.test/project.git",
      "http://example.test/project.git", "ssh://example.test/project.git?x=1",
      "file:///srv/project.git#main" ]

    expect(urls).to all(satisfy { |url| expect { described_class.normalize(url) }.to raise_error(described_class::Invalid) })
  end
end
