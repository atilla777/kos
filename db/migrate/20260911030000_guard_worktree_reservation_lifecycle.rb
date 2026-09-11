class GuardWorktreeReservationLifecycle < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE TRIGGER worktree_reservations_lifecycle
      BEFORE UPDATE OF state ON worktree_reservations
      WHEN NOT (
        (OLD.state = 'reserved' AND NEW.state IN ('reserved', 'confirmed'))
        OR (OLD.state = 'confirmed' AND NEW.state IN ('confirmed', 'released'))
        OR (OLD.state = 'confirmed' AND NEW.state = 'release_pending'
          AND NEW.observed_state = 'clean' AND NEW.observation_digest IS NOT NULL
          AND NEW.head_sha = OLD.head_sha)
        OR (OLD.state = 'release_pending' AND NEW.state IN ('release_pending', 'released'))
        OR (OLD.state = 'released' AND NEW.state = 'released')
      )
      BEGIN
        SELECT RAISE(ABORT, 'invalid worktree reservation lifecycle transition');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER worktree_reservations_confirmation_immutable
      BEFORE UPDATE OF git_common_dir_digest, head_sha, confirmed_at ON worktree_reservations
      WHEN (OLD.git_common_dir_digest IS NOT NULL AND NEW.git_common_dir_digest IS NOT OLD.git_common_dir_digest)
        OR (OLD.confirmed_at IS NOT NULL AND NEW.confirmed_at IS NOT OLD.confirmed_at)
        OR (OLD.state = 'release_pending' AND NEW.head_sha IS NOT OLD.head_sha)
      BEGIN
        SELECT RAISE(ABORT, 'worktree reservation confirmation identity is immutable');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER worktree_reservations_released_immutable
      BEFORE UPDATE ON worktree_reservations
      WHEN OLD.state = 'released'
      BEGIN
        SELECT RAISE(ABORT, 'released worktree reservation is immutable');
      END;
    SQL
  end

  def down
    execute "DROP TRIGGER IF EXISTS worktree_reservations_released_immutable"
    execute "DROP TRIGGER IF EXISTS worktree_reservations_confirmation_immutable"
    execute "DROP TRIGGER IF EXISTS worktree_reservations_lifecycle"
  end
end
