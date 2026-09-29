class UniqueGlobalWorkflowNames < ActiveRecord::Migration[8.1]
  def change
    add_index :workflows, :name, unique: true, where: "project_id IS NULL", name: "index_global_workflows_on_name"
  end
end
