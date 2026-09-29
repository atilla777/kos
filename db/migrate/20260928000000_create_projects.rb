class CreateProjects < ActiveRecord::Migration[8.1]
  def change
    create_table :projects do |t|
      t.string :repository, null: false
      t.string :name, null: false

      t.timestamps
    end

    add_index :projects, :repository, unique: true
  end
end
