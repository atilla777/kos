# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_29_000008) do
  create_table "projects", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "repository", null: false
    t.datetime "updated_at", null: false
    t.index ["repository"], name: "index_projects_on_repository", unique: true
  end

  create_table "task_artifacts", force: :cascade do |t|
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.integer "lock_version", default: 0, null: false
    t.integer "task_id", null: false
    t.datetime "updated_at", null: false
    t.index ["task_id", "key"], name: "index_task_artifacts_on_task_id_and_key", unique: true
    t.index ["task_id"], name: "index_task_artifacts_on_task_id"
    t.check_constraint "length(trim(key)) > 0", name: "task_artifacts_key_not_blank"
    t.check_constraint "lock_version >= 0", name: "task_artifacts_lock_version_not_negative"
  end

  create_table "task_dependencies", force: :cascade do |t|
    t.integer "blocking_task_id", null: false
    t.datetime "created_at", null: false
    t.integer "project_id", null: false
    t.integer "task_id", null: false
    t.datetime "updated_at", null: false
    t.index ["blocking_task_id", "project_id"], name: "index_task_dependencies_on_blocking_task_id_and_project_id"
    t.index ["task_id", "blocking_task_id"], name: "index_task_dependencies_on_task_id_and_blocking_task_id", unique: true
    t.index ["task_id", "project_id"], name: "index_task_dependencies_on_task_id_and_project_id"
    t.check_constraint "task_id != blocking_task_id", name: "task_dependencies_not_self_referential"
  end

  create_table "task_groups", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description", null: false
    t.string "kind", null: false
    t.integer "project_id", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["id", "project_id"], name: "index_task_groups_on_id_and_project_id", unique: true
    t.index ["project_id"], name: "index_task_groups_on_project_id"
    t.check_constraint "kind = 'epic'", name: "task_groups_kind_allowed"
    t.check_constraint "length(trim(description)) > 0", name: "task_groups_description_present"
    t.check_constraint "length(trim(title)) > 0", name: "task_groups_title_present"
  end

  create_table "tasks", force: :cascade do |t|
    t.string "claim_id"
    t.datetime "claimed_at"
    t.datetime "created_at", null: false
    t.integer "current_step", default: 0, null: false
    t.text "description", null: false
    t.string "kind", null: false
    t.datetime "lease_expires_at"
    t.integer "project_id", null: false
    t.string "session_id"
    t.string "status", default: "planned", null: false
    t.integer "task_group_id"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.text "work_summary"
    t.integer "workflow_id", null: false
    t.index ["claim_id"], name: "index_tasks_on_claim_id", unique: true, where: "claim_id IS NOT NULL"
    t.index ["id", "project_id"], name: "index_tasks_on_id_and_project_id", unique: true
    t.index ["project_id", "session_id", "lease_expires_at"], name: "index_tasks_on_project_session_and_lease", where: "status = 'in_progress'"
    t.index ["project_id"], name: "index_tasks_on_project_id"
    t.index ["task_group_id"], name: "index_tasks_on_task_group_id"
    t.index ["workflow_id"], name: "index_tasks_on_workflow_id"
    t.check_constraint "(status = 'in_progress' AND session_id IS NOT NULL AND length(trim(session_id)) > 0 AND claim_id IS NOT NULL AND length(trim(claim_id)) > 0 AND claimed_at IS NOT NULL AND lease_expires_at IS NOT NULL AND lease_expires_at > claimed_at) OR (status IN ('planned', 'done') AND session_id IS NULL AND claim_id IS NULL AND claimed_at IS NULL AND lease_expires_at IS NULL)", name: "tasks_status_ownership_consistent"
    t.check_constraint "current_step >= 0", name: "tasks_current_step_nonnegative"
    t.check_constraint "length(trim(description)) > 0", name: "tasks_description_present"
    t.check_constraint "length(trim(kind)) > 0", name: "tasks_kind_present"
    t.check_constraint "length(trim(title)) > 0", name: "tasks_title_present"
    t.check_constraint "status IN ('planned', 'in_progress', 'done')", name: "tasks_status_allowed"
  end

  create_table "workflows", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "project_id", null: false
    t.json "steps", null: false
    t.datetime "updated_at", null: false
    t.index ["id", "project_id"], name: "index_workflows_on_id_and_project_id", unique: true
    t.index ["project_id"], name: "index_workflows_on_project_id"
    t.check_constraint "length(trim(name)) > 0", name: "workflows_name_present"
  end

  add_foreign_key "task_artifacts", "tasks", on_delete: :cascade
  add_foreign_key "task_dependencies", "tasks", column: ["blocking_task_id", "project_id"], primary_key: ["id", "project_id"], on_delete: :restrict
  add_foreign_key "task_dependencies", "tasks", column: ["task_id", "project_id"], primary_key: ["id", "project_id"], on_delete: :cascade
  add_foreign_key "task_groups", "projects", on_delete: :restrict
  add_foreign_key "tasks", "projects", on_delete: :restrict
  add_foreign_key "tasks", "task_groups", column: ["task_group_id", "project_id"], primary_key: ["id", "project_id"], on_delete: :restrict
  add_foreign_key "tasks", "workflows", column: ["workflow_id", "project_id"], primary_key: ["id", "project_id"], on_delete: :restrict
  add_foreign_key "workflows", "projects", on_delete: :restrict
end
