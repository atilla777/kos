class AddTaskExecutionContext < ActiveRecord::Migration[8.1]
  def change
    add_column :tasks, :accepted_artifacts, :json, null: false, default: {}
    add_column :tasks, :pause_message, :text
    add_column :tasks, :pause_step, :string
    add_column :tasks, :pause_claim_version, :integer
    add_column :tasks, :human_answer, :text
    add_column :tasks, :human_answer_step, :string
    add_column :tasks, :human_answer_claim_version, :integer
  end
end
