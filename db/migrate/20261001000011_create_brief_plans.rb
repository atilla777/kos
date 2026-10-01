class CreateBriefPlans < ActiveRecord::Migration[8.1]
  def change
    create_table :brief_plans do |t|
      t.references :brief_task, null: false, index: { unique: true }, foreign_key: { to_table: :tasks, on_delete: :restrict }
      t.string :request_key, null: false
      t.string :request_digest, null: false
      t.json :result, null: false
      t.timestamps
    end

    add_check_constraint :brief_plans, "length(trim(request_key)) > 0", name: "brief_plans_key_present"
  end
end
