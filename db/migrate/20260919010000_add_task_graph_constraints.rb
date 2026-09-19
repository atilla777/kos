class AddTaskGraphConstraints < ActiveRecord::Migration[8.1]
  def change
    add_check_constraint :tasks, "parent_id IS NULL OR parent_id != id", name: "tasks_parent_not_self"
    add_check_constraint :task_dependencies, "task_id != blocker_id", name: "task_dependencies_not_self"
  end
end
