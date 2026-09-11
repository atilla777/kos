require "digest"
require "open3"

module RepositoryEvidence
  class VerifyArtifacts
    Verification = Data.define(:repository_id, :task_number, :manifest_digest)

    def self.call(repository:, task_number:, artifacts:)
      artifacts.each do |artifact|
        case artifact.fetch("type")
        when "document"
          verify_document!(repository, task_number, artifact.fetch("metadata"))
        when "candidate"
          verify_candidate!(repository, task_number, artifact.fetch("metadata"))
        end
      end

      Verification.new(repository.id, task_number, manifest_digest(artifacts))
    end

    def self.matches?(verification, repository:, task_number:, artifacts:)
      verification == Verification.new(repository.id, task_number, manifest_digest(artifacts))
    end

    def self.verify_document!(repository, task_number, metadata)
      invalid!("Document path contains a null byte") if metadata.fetch("path").include?("\0")
      unless metadata.fetch("path").start_with?("tasks/#{task_number}/")
        invalid!("Document path does not belong to the owning task")
      end
      invalid!("Document commit is not a Git commit") unless
        git!(repository, "cat-file", "-t", metadata.fetch("commit_sha")).strip == "commit"

      object = "#{metadata.fetch("commit_sha")}:#{metadata.fetch("path")}"
      type = git!(repository, "cat-file", "-t", object).strip
      invalid!("Document path does not identify a Git blob") unless type == "blob"

      content = git!(repository, "cat-file", "blob", object)
      actual = "sha256:#{Digest::SHA256.hexdigest(content)}"
      invalid!("Document content digest does not match Git") unless actual == metadata.fetch("content_digest")
    end
    private_class_method :verify_document!

    def self.verify_candidate!(repository, task_number, metadata)
      sha = metadata.fetch("candidate_sha")
      invalid!("Candidate does not identify a Git commit") unless git!(repository, "cat-file", "-t", sha).strip == "commit"
      trailers = git!(repository, "show", "-s", "--format=%(trailers:key=KOS-Task,valueonly)", sha)
        .lines.map(&:strip).reject(&:empty?)
      valid = metadata.fetch("task_trailer") == task_number && trailers == [ task_number ]
      invalid!("Candidate task trailer does not match the owning task") unless valid
    end
    private_class_method :verify_candidate!

    def self.git!(repository, *arguments)
      environment = { "PATH" => ENV.fetch("PATH", "/usr/bin:/bin"), "LC_ALL" => "C",
        "GIT_CONFIG_NOSYSTEM" => "1", "GIT_CONFIG_GLOBAL" => "/dev/null", "GIT_NO_LAZY_FETCH" => "1" }
      stdout, _stderr, status = Open3.capture3(environment, "git", "--no-replace-objects",
        "--git-dir=#{repository.git_common_dir}", *arguments, unsetenv_others: true)
      invalid!("Artifact Git evidence is unavailable") unless status.success?

      stdout
    end
    private_class_method :git!

    def self.manifest_digest(artifacts)
      canonical = WorkflowCatalog::CanonicalDefinition.canonical_json(artifacts)
      "sha256:#{Digest::SHA256.hexdigest(canonical)}"
    end
    private_class_method :manifest_digest

    def self.invalid!(message)
      raise OperationError.new("invalid_artifact", message)
    end
    private_class_method :invalid!
  end
end
