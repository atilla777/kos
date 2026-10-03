class UniqueProjectWorkflowEditions < ActiveRecord::Migration[8.1]
  def change
    add_index :workflows, %i[project_id name], unique: true,
      where: "base_workflow_id IS NOT NULL", name: "index_project_workflow_editions_on_name"
  end
end
