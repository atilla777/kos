require "test_helper"
require "json"
require "net/http"
require "rbconfig"
require "socket"
require "tempfile"
require "timeout"

class AcceptanceScenariosTest < ActiveSupport::TestCase
  include GitRepositoryHelpers

  test "a moved base repeats checks and review before one publication commit" do
    with_repository do |repository|
      task, lifecycle = claimed_acceptance_task
      worktree = repository[:root].join("data/worktrees/#{task.project_id}/#{task.id}")
      git("worktree", "add", "--detach", worktree.to_s, "origin/main", chdir: repository[:source])
      previous_base = git("rev-parse", "HEAD", chdir: worktree).strip
      File.write(worktree.join("README.md"), "staged task change\n")
      git("add", "README.md", chdir: worktree)
      File.open(worktree.join("README.md"), "a") { |file| file.write("unstaged task change\n") }
      File.write(worktree.join("task.txt"), "task change\n")

      task = report(lifecycle, task, "develop", "ready")
      task = run_checks(lifecycle, task, worktree, repository[:root], attempt: 1)
      task = run_read_only_review(lifecycle, task, worktree, repository[:root], attempt: 1)
      assert_equal "publish", task.current_step

      File.write(repository[:publisher].join("base.txt"), "base change\n")
      git("add", "base.txt", chdir: repository[:publisher])
      git("commit", "-m", "Move base", chdir: repository[:publisher])
      git("push", "origin", "main", chdir: repository[:publisher])
      git("fetch", "--no-tags", "origin", "refs/heads/main:refs/remotes/origin/main", chdir: repository[:source])
      moved_base = git("rev-parse", "origin/main", chdir: repository[:source]).strip
      assert git_success?("merge-base", "--is-ancestor", previous_base, moved_base, chdir: worktree)

      git("reset", "--mixed", "HEAD", chdir: worktree)
      git("checkout", "--merge", "--detach", moved_base, chdir: worktree)
      task = report(lifecycle, task, "publish", "base_moved")

      assert_equal "check", task.current_step
      assert_equal moved_base, git("rev-parse", "HEAD", chdir: worktree).strip
      assert_equal "staged task change\nunstaged task change\n", File.read(worktree.join("README.md"))
      assert_equal "task change\n", File.read(worktree.join("task.txt"))
      status = git("status", "--porcelain", chdir: worktree)
      assert_includes status, " M README.md"
      assert_includes status, "?? task.txt"

      task = run_checks(lifecycle, task, worktree, repository[:root], attempt: 2)
      task = run_read_only_review(lifecycle, task, worktree, repository[:root], attempt: 2)
      assert_includes File.read(repository[:root].join("data/tasks/#{task.id}/check.md")), "Attempt 2"
      assert_includes File.read(repository[:root].join("data/tasks/#{task.id}/review.md")), "Attempt 2"
      git("add", "README.md", "task.txt", chdir: worktree)
      git("commit", "-m", "KOS task #{task.id}: #{task.title}", "-m", "KOS-Task: #{task.id}", chdir: worktree)
      candidate = git("rev-parse", "HEAD", chdir: worktree).strip
      git("push", "origin", "#{candidate}:refs/heads/main", chdir: worktree)
      task = report(lifecycle, task, "publish", "published")

      assert_equal "completed", task.status
      assert_equal candidate, git("--git-dir", repository[:remote].to_s, "rev-parse", "refs/heads/main").strip
      assert_equal "3", git("--git-dir", repository[:remote].to_s, "rev-list", "--count", "main").strip
      assert_equal moved_base, git("rev-parse", "#{candidate}^", chdir: worktree).strip
    end
  end

  test "two tasks retain independent ownership artifacts and uncommitted worktrees" do
    with_repository do |repository|
      project = create_project(remote_url: repository[:remote].to_s)
      workflow = create_workflow(definition: acceptance_workflow_definition)
      task_type = create_task_type(name: "Acceptance", workflow:)
      first = create_task(project:, workflow:, task_type:, title: "First")
      second = create_task(project:, workflow:, task_type:, title: "Second")
      lifecycle = TaskLifecycle.new

      first_claim = lifecycle.claim_next!(project:, owner_id: "owner-a")
      second_claim = lifecycle.claim_next!(project:, owner_id: "owner-b")
      assert_equal [ first.id, second.id ], [ first_claim.id, second_claim.id ]

      first_worktree = repository[:root].join("data/worktrees/#{project.id}/#{first.id}")
      second_worktree = repository[:root].join("data/worktrees/#{project.id}/#{second.id}")
      git("worktree", "add", "--detach", first_worktree.to_s, "origin/main", chdir: repository[:source])
      git("worktree", "add", "--detach", second_worktree.to_s, "origin/main", chdir: repository[:source])
      File.write(first_worktree.join("first.txt"), "first task\n")
      File.write(second_worktree.join("second.txt"), "second task\n")

      first_artifact = repository[:root].join("data/tasks/#{first.id}/develop.md")
      second_artifact = repository[:root].join("data/tasks/#{second.id}/develop.md")
      write_artifact_durably(first_artifact, "# First\n")
      write_artifact_durably(second_artifact, "# Second\n")
      report(lifecycle, first_claim, "develop", "ready")

      assert_equal [ "check", "owner-a" ], first.reload.values_at(:current_step, :owner_id)
      assert_equal [ "develop", "owner-b" ], second.reload.values_at(:current_step, :owner_id)
      assert_equal "# First\n", File.read(first_artifact)
      assert_equal "# Second\n", File.read(second_artifact)
      assert_includes git("status", "--porcelain", chdir: first_worktree), "first.txt"
      refute_includes git("status", "--porcelain", chdir: first_worktree), "second.txt"
      assert_includes git("status", "--porcelain", chdir: second_worktree), "second.txt"
      refute_includes git("status", "--porcelain", chdir: second_worktree), "first.txt"
      assert_equal "1", git("rev-list", "--count", "HEAD", chdir: first_worktree).strip
      assert_equal "1", git("rev-list", "--count", "HEAD", chdir: second_worktree).strip
    end
  end

  test "publication recovery reuses the candidate before and after push" do
    [ false, true ].each do |push_before_restart|
      with_repository do |repository|
        worktree = repository[:root].join("data/worktrees/1/31")
        git("worktree", "add", "--detach", worktree.to_s, "origin/main", chdir: repository[:source])
        File.write(worktree.join("task.txt"), "published task\n")
        git("add", "task.txt", chdir: worktree)
        reviewed_patch = repository[:root].join("reviewed.patch")
        write_artifact_durably(reviewed_patch, git("diff", "--cached", "--binary", chdir: worktree))
        git("commit", "-m", "KOS task 31: Publish", "-m", "KOS-Task: 31", chdir: worktree)
        expected_candidate = git("rev-parse", "HEAD", chdir: worktree).strip
        expected_count = git("rev-list", "--count", "HEAD", chdir: worktree).strip
        git("push", "origin", "#{expected_candidate}:refs/heads/main", chdir: worktree) if push_before_restart

        output, error, status = Open3.capture3(RbConfig.ruby,
          Rails.root.join("test/support/publication_recovery_process.rb").to_s,
          worktree.to_s, repository[:source].to_s, "31", "Publish", JSON.generate([ "task.txt" ]),
          reviewed_patch.to_s)
        assert_predicate status, :success?, error
        recovered = JSON.parse(output)

        assert_equal expected_candidate, recovered.fetch("candidate")
        assert_equal expected_count, recovered.fetch("commit_count")
        assert_equal !push_before_restart, recovered.fetch("pushed")
        assert_equal expected_candidate,
          git("--git-dir", repository[:remote].to_s, "rev-parse", "refs/heads/main").strip
        assert_equal "31", git("log", "-1", "--format=%(trailers:key=KOS-Task,valueonly)", chdir: worktree).strip
        assert_empty git("status", "--porcelain", chdir: worktree)
      end
    end
  end

  private

  def create_project(name: "Project", remote_url: "https://example.test/project.git")
    Project.create!(name:, remote_url:, default_branch: "main")
  end

  def claimed_acceptance_task
    project = create_project
    workflow = create_workflow(definition: acceptance_workflow_definition)
    task_type = create_task_type(name: "Acceptance", workflow:)
    create_task(project:, workflow:, task_type:, title: "Publish")
    lifecycle = TaskLifecycle.new
    [ lifecycle.claim_next!(project:, owner_id: "owner"), lifecycle ]
  end

  def report(lifecycle, task, step, outcome)
    lifecycle.report_attempt!(task_id: task.id, owner_id: task.owner_id, claim_version: task.claim_version,
      step:, outcome:)
  end

  def run_checks(lifecycle, task, worktree, root, attempt:)
    git("diff", "--check", chdir: worktree)
    write_artifact_durably(root.join("data/tasks/#{task.id}/check.md"), "# Checks\n\nAttempt #{attempt}: passed.\n")
    report(lifecycle, task, "check", "passed")
  end

  def run_read_only_review(lifecycle, task, worktree, root, attempt:)
    head = git("rev-parse", "HEAD", chdir: worktree)
    status = git("status", "--porcelain=v2", "--untracked-files=all", "-z", chdir: worktree)
    output, error, review_status = Open3.capture3(RbConfig.ruby,
      Rails.root.join("test/support/read_only_review_process.rb").to_s,
      worktree.to_s, JSON.generate([ "README.md", "task.txt" ]))
    assert_predicate review_status, :success?, error
    review = JSON.parse(output)
    assert_equal [ "README.md", "task.txt" ], review.fetch("paths")
    assert_includes review.fetch("tracked_patch"), "staged task change"
    assert_equal "staged task change\nunstaged task change\n", review.dig("contents", "README.md")
    assert_equal "task change\n", review.dig("contents", "task.txt")
    assert_equal head, git("rev-parse", "HEAD", chdir: worktree)
    assert_equal status, git("status", "--porcelain=v2", "--untracked-files=all", "-z", chdir: worktree)
    write_artifact_durably(root.join("data/tasks/#{task.id}/review.md"), "# Review\n\nAttempt #{attempt}: approved.\n")
    report(lifecycle, task, "review", "approved")
  end

  def write_artifact_durably(path, content)
    FileUtils.mkdir_p(path.dirname)
    Tempfile.create([ ".artifact-", ".tmp" ], path.dirname) do |file|
      file.binmode
      file.write(content)
      file.flush
      file.fsync
      File.rename(file.path, path)
    end
    File.open(path.dirname, File::RDONLY, &:fsync)
  end
end

class RestartRecoveryScenarioTest < ActiveSupport::TestCase
  test "task state and durable artifact survive server and orchestrator restart" do
    with_running_system do |system|
      resources = create_resources(system)
      claim = run_kos_json(system, "task", "claim-next", "--project-id", resources.fetch(:project_id).to_s,
        "--owner-id", "session-before-restart")
      task = claim.fetch("task")
      artifact = system.fetch(:data_home).join("tasks/#{task.fetch("id")}/develop.md")
      write_artifact_durably(artifact, "# Development\n\nReady.\n")
      advanced = run_kos_json(system, "task", "report-attempt", task.fetch("id").to_s,
        "--owner-id", "session-before-restart", "--claim-version", "1", "--step", "develop", "--outcome", "ready")
      assert_equal "check", advanced.dig("task", "current_step")

      restart_server(system)
      shown = run_kos_json(system, "task", "show", task.fetch("id").to_s)
      resumed = run_kos_json(system, "task", "resume", task.fetch("id").to_s,
        "--owner-id", "session-after-restart", "--takeover-confirmed")

      assert_equal [ "active", "check", 2 ], shown.fetch("task").values_at("status", "current_step", "claim_version")
      assert_equal resources.fetch(:workflow_id), shown.dig("task", "workflow_id")
      assert_equal "# Development\n\nReady.\n", File.binread(artifact)
      assert_predicate artifact, :file?
      refute_predicate artifact, :symlink?
      assert_empty Dir.glob(artifact.dirname.join(".artifact-*.tmp"))
      assert_equal [ "session-after-restart", "check", 3 ],
        resumed.fetch("task").values_at("owner_id", "current_step", "claim_version")
    end
  end

  test "a dropped report response is recovered by show without a duplicate transition" do
    with_running_system do |system|
      resources = create_resources(system)
      claim = run_kos_json(system, "task", "claim-next", "--project-id", resources.fetch(:project_id).to_s,
        "--owner-id", "session")
      task_id = claim.dig("task", "id")
      proxy = dropping_proxy(system.fetch(:port))

      _output, error, status = run_kos(system, "task", "report-attempt", task_id.to_s,
        "--owner-id", "session", "--claim-version", "1", "--step", "develop", "--outcome", "ready",
        api_url: proxy.fetch(:url))
      joined = proxy.fetch(:thread).join(5)
      cleanup_proxy(proxy)
      assert joined, "response-dropping proxy did not finish"
      assert_empty proxy.fetch(:errors)
      assert_equal 3, status.exitstatus
      assert_equal "transport_error", JSON.parse(error).fetch("error")

      shown = run_kos_json(system, "task", "show", task_id.to_s)
      assert_equal [ "active", "check", "session", 2 ],
        shown.fetch("task").values_at("status", "current_step", "owner_id", "claim_version")

      output, stale_error, stale_status = run_kos(system, "task", "report-attempt", task_id.to_s,
        "--owner-id", "session", "--claim-version", "1", "--step", "develop", "--outcome", "ready")
      assert_equal 1, stale_status.exitstatus
      assert_empty stale_error
      assert_equal "conflict", JSON.parse(output).fetch("error")
      assert_equal 2, run_kos_json(system, "task", "show", task_id.to_s).dig("task", "claim_version")
    end
  end

  private

  def with_running_system
    Dir.mktmpdir("kos-system") do |directory|
      root = Pathname(directory)
      system = {
        data_home: root.join("data"), token: "integration-secret",
        log: root.join("server.log"), pid: nil
      }
      prepare_database(system)
      start_server(system)
      yield system
    ensure
      stop_server(system) if system
    end
  end

  def prepare_database(system)
    _output, error, status = Open3.capture3(server_environment(system), Rails.root.join("bin/rails").to_s, "db:prepare")
    assert_predicate status, :success?, error
  end

  def start_server(system)
    3.times do
      system[:port] = available_port
      system[:api_url] = "http://127.0.0.1:#{system.fetch(:port)}"
      system[:pid] = Process.spawn(server_environment(system), Rails.root.join("bin/rails").to_s, "server",
        "--binding", "127.0.0.1", "--port", system.fetch(:port).to_s,
        "--pid", system.fetch(:data_home).join("server.pid").to_s,
        out: system.fetch(:log).to_s, err: system.fetch(:log).to_s, pgroup: true)
      started = Timeout.timeout(15) do
        loop do
          if Process.waitpid(system.fetch(:pid), Process::WNOHANG)
            system[:pid] = nil
            break false
          end
          response = Net::HTTP.start("127.0.0.1", system.fetch(:port), open_timeout: 0.2, read_timeout: 0.2) do |http|
            http.get("/up")
          end
          break true if response.is_a?(Net::HTTPSuccess)
        rescue Errno::ECONNREFUSED, EOFError, Net::OpenTimeout, Net::ReadTimeout
          sleep 0.05
        end
      end
      return if started
    end
    flunk("Rails server exited before binding:\n#{File.read(system.fetch(:log))}")
  rescue Timeout::Error
    flunk("Rails server did not start:\n#{File.read(system.fetch(:log))}")
  end

  def stop_server(system)
    return unless system[:pid]

    Process.kill("TERM", -system.fetch(:pid))
    Timeout.timeout(10) { Process.wait(system.fetch(:pid)) }
  rescue Errno::ESRCH, Errno::ECHILD
    nil
  rescue Timeout::Error
    Process.kill("KILL", -system.fetch(:pid))
    Process.wait(system.fetch(:pid))
  ensure
    system[:pid] = nil
  end

  def restart_server(system)
    stop_server(system)
    start_server(system)
  end

  def server_environment(system)
    {
      "RAILS_ENV" => "development", "KOS_API_TOKEN" => system.fetch(:token),
      "KOS_DATA_HOME" => system.fetch(:data_home).to_s, "RAILS_LOG_TO_STDOUT" => "1",
      "DATABASE_URL" => nil
    }
  end

  def create_resources(system)
    project = run_kos_json(system, "project", "create", "--name", "Acceptance", "--remote-url",
      "https://example.test/acceptance.git", "--default-branch", "main").fetch("project")
    Tempfile.create([ "workflow", ".json" ]) do |workflow_file|
      workflow_file.write(JSON.generate(acceptance_workflow_definition))
      workflow_file.flush
      workflow = run_kos_json(system, "workflow", "create", "--name", "Acceptance",
        "--definition-file", workflow_file.path).fetch("workflow")
      task_type = run_kos_json(system, "task-type", "create", "--key", "acceptance", "--name", "Acceptance", "--workflow-id",
        workflow.fetch("id").to_s).fetch("task_type")
      Tempfile.create([ "task", ".md" ]) do |description_file|
        description_file.write("Integration task\n")
        description_file.flush
        run_kos_json(system, "task", "create", "--project-id", project.fetch("id").to_s, "--task-type-id",
          task_type.fetch("id").to_s, "--title", "Integration", "--description-file", description_file.path)
      end
      return { project_id: project.fetch("id"), workflow_id: workflow.fetch("id") }
    end
  end

  def run_kos_json(system, *arguments)
    output, error, status = run_kos(system, *arguments)
    assert_predicate status, :success?, "#{arguments.join(" ")} failed:\n#{output}#{error}"
    JSON.parse(output)
  end

  def run_kos(system, *arguments, api_url: system.fetch(:api_url))
    environment = {
      "RUBYOPT" => nil, "RUBYLIB" => nil, "KOS_API_URL" => api_url,
      "KOS_API_TOKEN" => system.fetch(:token)
    }
    Open3.capture3(environment, RbConfig.ruby, "--disable-gems", Rails.root.join("bin/kos").to_s, *arguments)
  end

  def dropping_proxy(upstream_port)
    server = TCPServer.new("127.0.0.1", 0)
    errors = Queue.new
    thread = Thread.new do
      client = nil
      upstream = nil
      Timeout.timeout(5) do
        client = server.accept
        upstream = TCPSocket.new("127.0.0.1", upstream_port)
        request = read_http_message(client)
        upstream.write(request)
        read_http_message(upstream)
      end
    rescue StandardError => error
      errors << error unless error.is_a?(IOError) && server.closed?
    ensure
      upstream&.close
      client&.close
      server.close unless server.closed?
    end
    thread.report_on_exception = false
    { url: "http://127.0.0.1:#{server.local_address.ip_port}", thread:, server:, errors: }
  end

  def cleanup_proxy(proxy)
    proxy.fetch(:server).close unless proxy.fetch(:server).closed?
    return unless proxy.fetch(:thread).alive?

    proxy.fetch(:thread).kill
    proxy.fetch(:thread).join
  end

  def read_http_message(socket)
    message = +""
    message << socket.readpartial(4096) until message.include?("\r\n\r\n")
    header, body = message.split("\r\n\r\n", 2)
    length = header[/^Content-Length:\s*(\d+)/i, 1].to_i
    body << socket.read(length - body.bytesize) if body.bytesize < length
    "#{header}\r\n\r\n#{body}"
  end

  def available_port
    server = TCPServer.new("127.0.0.1", 0)
    server.local_address.ip_port
  ensure
    server&.close
  end

  def write_artifact_durably(path, content)
    FileUtils.mkdir_p(path.dirname)
    Tempfile.create([ ".artifact-", ".tmp" ], path.dirname) do |file|
      file.binmode
      file.write(content)
      file.flush
      file.fsync
      File.rename(file.path, path)
    end
    File.open(path.dirname, File::RDONLY, &:fsync)
  end
end
