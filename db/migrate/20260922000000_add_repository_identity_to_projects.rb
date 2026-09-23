class AddRepositoryIdentityToProjects < ActiveRecord::Migration[8.1]
  def up
    transaction do
      add_column :projects, :repository_identity, :string

      Project.reset_column_information
      Project.find_each do |project|
        project.update_columns(repository_identity: RepositoryIdentity.normalize(project.remote_url))
      end

      change_column_null :projects, :repository_identity, false
      add_index :projects, :repository_identity, unique: true
    end
  end

  def down
    remove_index :projects, :repository_identity
    remove_column :projects, :repository_identity
  end
end
