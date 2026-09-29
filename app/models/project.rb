class Project < ApplicationRecord
  CANONICAL_REPOSITORY_PATTERN = %r{\A(?<host>[a-zA-Z0-9.-]+(?::[0-9]+)?)/(?<path>[A-Za-z0-9._~/-]+)\z}

  has_many :tasks, dependent: :restrict_with_error
  has_many :task_groups, dependent: :restrict_with_error
  has_many :workflows, dependent: :restrict_with_error

  before_validation :canonicalize_repository

  validates :name, presence: true
  validates :repository,
    presence: true,
    uniqueness: true,
    format: {
      with: /\A[a-z0-9.-]+(?::[0-9]+)?\/[A-Za-z0-9._~\/-]+\z/,
      message: "must be a canonical repository key such as github.com/owner/repository"
    }

  def self.normalize_repository(repository)
    match = CANONICAL_REPOSITORY_PATTERN.match(repository.to_s)
    return unless match

    host = match[:host].downcase
    path = match[:path].sub(%r{/+\z}, "").sub(/\.git\z/i, "")
    path = path.downcase if host == "github.com"
    "#{host}/#{path}"
  end

  private

  def canonicalize_repository
    self.repository = self.class.normalize_repository(repository) || repository
  end
end
