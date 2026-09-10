require "rails_helper"

RSpec.describe Kos::State::Layout do
  let(:temporary_directory) { Pathname.new(Dir.mktmpdir("kos-state-layout")) }

  after { FileUtils.remove_entry(temporary_directory) }

  describe ".resolve" do
    it "uses the state-root override before XDG and HOME" do
      layout = described_class.resolve(environment: path_environment)

      expect([ layout.root_path, layout.database_path ]).to eq([
        temporary_directory.join("override"), temporary_directory.join("override/kos.sqlite3")
      ])
    end

    it "uses XDG state when there is no override" do
      layout = described_class.resolve(environment: path_environment.except("KOS_STATE_ROOT"))

      expect(layout.root_path).to eq(temporary_directory.join("xdg/kos"))
    end

    it "falls back to HOME when XDG state is absent" do
      layout = described_class.resolve(environment: { "HOME" => temporary_directory.join("home").to_s })

      expect(layout.root_path).to eq(temporary_directory.join("home/.local/state/kos"))
    end

    it "rejects a relative state root" do
      expect { described_class.resolve(environment: { "KOS_STATE_ROOT" => "relative" }) }
        .to raise_error(Kos::State::Error, /KOS_STATE_ROOT must be an absolute path/)
    end

    it "rejects a relative database override" do
      environment = { "KOS_STATE_ROOT" => temporary_directory.to_s, "KOS_DATABASE_PATH" => "relative.sqlite3" }

      expect { described_class.resolve(environment:) }
        .to raise_error(Kos::State::Error, /KOS_DATABASE_PATH must be an absolute path/)
    end

    it "rejects an environment without an absolute fallback" do
      expect { described_class.resolve(environment: {}) }
        .to raise_error(Kos::State::Error, /cannot be resolved/)
    end
  end

  describe "filesystem safety" do
    it "creates private state directories" do
      layout = build_layout("state").prepare!

      expect([ layout.root_path, layout.backups_path, layout.locks_path ].map { |path| path.stat.mode & 0o777 })
        .to all(eq(0o700))
    end

    it "rejects symlink components" do
      target = temporary_directory.join("target").tap { |path| path.mkdir(0o700) }
      temporary_directory.join("linked").make_symlink(target)

      expect { build_layout("linked/state").prepare! }
        .to raise_error(Kos::State::Error, /must not contain symlinks/)
    end

    it "rejects non-private state objects" do
      temporary_directory.join("open").mkdir(0o755)

      expect { build_layout("open").prepare! }
        .to raise_error(Kos::State::Error, /must not grant group or other permissions/)
    end

    it "rejects a path below an unsafe writable ancestor" do
      ancestor = temporary_directory.join("writable").tap { |path| path.mkdir; path.chmod(0o777) }

      expect { build_layout("writable/state").prepare! }
        .to raise_error(Kos::State::Error, /path component is writable by another user: #{ancestor}/)
    end

    it "rejects a sticky writable ancestor not owned by root or the effective user" do
      ancestor = temporary_directory.join("sticky").tap { |path| path.mkdir; path.chmod(0o1777) }
      layout = build_layout("sticky/state", effective_uid: Process.euid + 1)

      expect { layout.prepare! }
        .to raise_error(Kos::State::Error, /path component is writable by another user: #{ancestor}/)
    end

    it "rejects state objects owned by another user" do
      layout = build_layout("foreign", effective_uid: Process.euid + 1)

      expect { layout.prepare! }.to raise_error(Kos::State::Error, /different owner/)
    end

    it "rejects a database symlink even when its target is absent" do
      layout = build_layout("state").prepare!
      layout.database_path.make_symlink(temporary_directory.join("missing"))

      expect { layout.validate_database! }.to raise_error(Kos::State::Error, /not a regular file/)
    end

    it "creates a private database without following an existing path" do
      layout = build_layout("state").prepare!

      layout.create_database!

      expect(layout.database_path.stat.mode & 0o777).to eq(0o600)
    end

    it "rejects an orphan database sidecar" do
      layout = build_layout("state").prepare!
      File.write("#{layout.database_path}-wal", "orphan")
      File.chmod(0o600, "#{layout.database_path}-wal")

      expect { layout.prepare! }.to raise_error(Kos::State::Error, /sidecar exists without its database/)
    end
  end

  def path_environment
    {
      "KOS_STATE_ROOT" => temporary_directory.join("override").to_s,
      "XDG_STATE_HOME" => temporary_directory.join("xdg").to_s,
      "HOME" => temporary_directory.join("home").to_s
    }
  end

  def build_layout(relative_root, effective_uid: Process.euid)
    root = temporary_directory.join(relative_root)
    described_class.new(root_path: root, database_path: root.join("kos.sqlite3"), effective_uid:)
  end
end
