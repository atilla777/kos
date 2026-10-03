CREATE TABLE "schema_migrations" ("version" varchar NOT NULL PRIMARY KEY);
CREATE TABLE "ar_internal_metadata" ("key" varchar NOT NULL PRIMARY KEY, "value" varchar, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE TABLE "projects" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "repository" varchar NOT NULL, "name" varchar NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE UNIQUE INDEX "index_projects_on_repository" ON "projects" ("repository");
CREATE TABLE "task_groups" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "project_id" integer NOT NULL, "kind" varchar NOT NULL, "title" varchar NOT NULL, "description" text NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_cbd14c3ba3"
FOREIGN KEY ("project_id")
  REFERENCES "projects" ("id")
 ON DELETE RESTRICT, CONSTRAINT task_groups_kind_allowed CHECK (kind = 'epic'), CONSTRAINT task_groups_title_present CHECK (length(trim(title)) > 0), CONSTRAINT task_groups_description_present CHECK (length(trim(description)) > 0));
CREATE INDEX "index_task_groups_on_project_id" ON "task_groups" ("project_id");
CREATE UNIQUE INDEX "index_task_groups_on_id_and_project_id" ON "task_groups" ("id", "project_id");
CREATE TABLE "task_dependencies" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "task_id" integer NOT NULL, "blocking_task_id" integer NOT NULL, "project_id" integer NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_cf1b14dd48"
FOREIGN KEY ("task_id", "project_id")
  REFERENCES "tasks" ("id", "project_id")
 ON DELETE CASCADE, CONSTRAINT "fk_rails_9e6aab0a8a"
FOREIGN KEY ("blocking_task_id", "project_id")
  REFERENCES "tasks" ("id", "project_id")
 ON DELETE RESTRICT, CONSTRAINT task_dependencies_not_self_referential CHECK (task_id != blocking_task_id));
CREATE UNIQUE INDEX "index_task_dependencies_on_task_id_and_blocking_task_id" ON "task_dependencies" ("task_id", "blocking_task_id");
CREATE INDEX "index_task_dependencies_on_task_id_and_project_id" ON "task_dependencies" ("task_id", "project_id");
CREATE INDEX "index_task_dependencies_on_blocking_task_id_and_project_id" ON "task_dependencies" ("blocking_task_id", "project_id");
CREATE TABLE "task_artifacts" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "task_id" integer NOT NULL, "key" varchar NOT NULL, "content" text NOT NULL, "lock_version" integer DEFAULT 0 NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_4a71dd24a4"
FOREIGN KEY ("task_id")
  REFERENCES "tasks" ("id")
 ON DELETE CASCADE, CONSTRAINT task_artifacts_key_not_blank CHECK (length(trim(key)) > 0), CONSTRAINT task_artifacts_lock_version_not_negative CHECK (lock_version >= 0));
CREATE INDEX "index_task_artifacts_on_task_id" ON "task_artifacts" ("task_id");
CREATE UNIQUE INDEX "index_task_artifacts_on_task_id_and_key" ON "task_artifacts" ("task_id", "key");
CREATE TABLE "tasks" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "project_id" integer NOT NULL, "kind" varchar NOT NULL, "title" varchar NOT NULL, "description" text NOT NULL, "status" varchar DEFAULT 'planned' NOT NULL, "work_summary" text, "session_id" varchar, "claim_id" varchar, "claimed_at" datetime(6), "lease_expires_at" datetime(6), "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, "task_group_id" integer, "workflow_id" integer NOT NULL, "current_step" integer DEFAULT 0 NOT NULL, CONSTRAINT "fk_rails_bdd88292f8"
FOREIGN KEY ("task_group_id", "project_id")
  REFERENCES "task_groups" ("id", "project_id")
 ON DELETE RESTRICT, CONSTRAINT "fk_rails_02e851e3b7"
FOREIGN KEY ("project_id")
  REFERENCES "projects" ("id")
 ON DELETE RESTRICT, CONSTRAINT "fk_rails_025c576ee7"
FOREIGN KEY ("workflow_id")
  REFERENCES "workflows" ("id")
 ON DELETE RESTRICT, CONSTRAINT tasks_kind_present CHECK (length(trim(kind)) > 0), CONSTRAINT tasks_title_present CHECK (length(trim(title)) > 0), CONSTRAINT tasks_description_present CHECK (length(trim(description)) > 0), CONSTRAINT tasks_status_allowed CHECK (status IN ('planned', 'in_progress', 'done')), CONSTRAINT tasks_status_ownership_consistent CHECK ((status = 'in_progress' AND session_id IS NOT NULL AND length(trim(session_id)) > 0 AND claim_id IS NOT NULL AND length(trim(claim_id)) > 0 AND claimed_at IS NOT NULL AND lease_expires_at IS NOT NULL AND lease_expires_at > claimed_at) OR (status IN ('planned', 'done') AND session_id IS NULL AND claim_id IS NULL AND claimed_at IS NULL AND lease_expires_at IS NULL)), CONSTRAINT tasks_current_step_nonnegative CHECK (current_step >= 0));
CREATE INDEX "index_tasks_on_project_id" ON "tasks" ("project_id");
CREATE INDEX "index_tasks_on_task_group_id" ON "tasks" ("task_group_id");
CREATE UNIQUE INDEX "index_tasks_on_id_and_project_id" ON "tasks" ("id", "project_id");
CREATE UNIQUE INDEX "index_tasks_on_claim_id" ON "tasks" ("claim_id") WHERE claim_id IS NOT NULL;
CREATE INDEX "index_tasks_on_project_session_and_lease" ON "tasks" ("project_id", "session_id", "lease_expires_at") WHERE status = 'in_progress';
CREATE INDEX "index_tasks_on_workflow_id" ON "tasks" ("workflow_id");
CREATE TRIGGER tasks_workflow_project_insert
BEFORE INSERT ON tasks
WHEN EXISTS (
  SELECT 1 FROM workflows
  WHERE id = NEW.workflow_id AND project_id IS NOT NULL AND project_id != NEW.project_id
)
BEGIN
  SELECT RAISE(ABORT, 'workflow must belong to the task project');
END;
CREATE TRIGGER tasks_workflow_project_update
BEFORE UPDATE ON tasks
WHEN EXISTS (
  SELECT 1 FROM workflows
  WHERE id = NEW.workflow_id AND project_id IS NOT NULL AND project_id != NEW.project_id
)
BEGIN
  SELECT RAISE(ABORT, 'workflow must belong to the task project');
END;
CREATE TABLE "brief_plans" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "brief_task_id" integer NOT NULL, "request_key" varchar NOT NULL, "request_digest" varchar NOT NULL, "result" json NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_eb1f6dcab2"
FOREIGN KEY ("brief_task_id")
  REFERENCES "tasks" ("id")
 ON DELETE RESTRICT, CONSTRAINT brief_plans_key_present CHECK (length(trim(request_key)) > 0));
CREATE UNIQUE INDEX "index_brief_plans_on_brief_task_id" ON "brief_plans" ("brief_task_id");
CREATE TRIGGER protect_brief_plan_blocker_delete
BEFORE DELETE ON task_dependencies
WHEN EXISTS (
  SELECT 1 FROM brief_plans plans, json_each(plans.result) children
  INNER JOIN tasks briefs ON briefs.id = plans.brief_task_id
  WHERE CAST(json_extract(children.value, '$.id') AS INTEGER) = OLD.task_id
    AND plans.brief_task_id = OLD.blocking_task_id
    AND briefs.status != 'done'
)
BEGIN
  SELECT RAISE(ABORT, 'brief blocker cannot be removed before completion');
END;
CREATE TRIGGER protect_brief_plan_blocker_update
BEFORE UPDATE ON task_dependencies
WHEN EXISTS (
  SELECT 1 FROM brief_plans plans, json_each(plans.result) children
  INNER JOIN tasks briefs ON briefs.id = plans.brief_task_id
  WHERE CAST(json_extract(children.value, '$.id') AS INTEGER) = OLD.task_id
    AND plans.brief_task_id = OLD.blocking_task_id
    AND briefs.status != 'done'
)
BEGIN
  SELECT RAISE(ABORT, 'brief blocker cannot be removed before completion');
END;
CREATE TABLE "workflows" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "project_id" integer, "name" varchar NOT NULL, "steps" json NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, "base_workflow_id" integer, "edition" integer, CONSTRAINT "fk_rails_382d2c48c7"
FOREIGN KEY ("project_id")
  REFERENCES "projects" ("id")
 ON DELETE RESTRICT, CONSTRAINT "fk_rails_dcf01c6a7e"
FOREIGN KEY ("base_workflow_id")
  REFERENCES "workflows" ("id")
 ON DELETE RESTRICT, CONSTRAINT workflows_name_present CHECK (length(trim(name)) > 0), CONSTRAINT workflows_edition_positive CHECK (edition IS NULL OR edition > 0), CONSTRAINT workflows_origin_complete CHECK ((base_workflow_id IS NULL AND edition IS NULL) OR (base_workflow_id IS NOT NULL AND edition IS NOT NULL AND project_id IS NOT NULL)));
CREATE INDEX "index_workflows_on_project_id" ON "workflows" ("project_id");
CREATE UNIQUE INDEX "index_workflows_on_id_and_project_id" ON "workflows" ("id", "project_id");
CREATE UNIQUE INDEX "index_global_workflows_on_name" ON "workflows" ("name") WHERE project_id IS NULL;
CREATE INDEX "index_workflows_on_base_workflow_id" ON "workflows" ("base_workflow_id");
CREATE UNIQUE INDEX "index_workflows_on_project_origin_edition" ON "workflows" ("project_id", "base_workflow_id", "edition");
CREATE TRIGGER workflows_project_immutable
BEFORE UPDATE OF project_id ON workflows
WHEN OLD.project_id IS NOT NEW.project_id
BEGIN
  SELECT RAISE(ABORT, 'workflow project cannot change');
END;
CREATE TRIGGER workflows_base_insert
BEFORE INSERT ON workflows
WHEN NEW.base_workflow_id IS NOT NULL AND NOT EXISTS (
  SELECT 1 FROM workflows WHERE id = NEW.base_workflow_id
    AND project_id IS NULL AND base_workflow_id IS NULL
)
BEGIN
  SELECT RAISE(ABORT, 'base workflow must be shared');
END;
CREATE TRIGGER workflows_base_update
BEFORE UPDATE ON workflows
WHEN NEW.base_workflow_id IS NOT NULL AND NOT EXISTS (
  SELECT 1 FROM workflows WHERE id = NEW.base_workflow_id
    AND project_id IS NULL AND base_workflow_id IS NULL
)
BEGIN
  SELECT RAISE(ABORT, 'base workflow must be shared');
END;
CREATE TRIGGER workflows_origin_immutable
BEFORE UPDATE OF base_workflow_id, edition ON workflows
WHEN OLD.base_workflow_id IS NOT NEW.base_workflow_id OR OLD.edition IS NOT NEW.edition
BEGIN
  SELECT RAISE(ABORT, 'workflow origin and edition cannot change');
END;
INSERT INTO "schema_migrations" (version) VALUES
('20261003000000'),
('20261001000012'),
('20261001000011'),
('20260929000010'),
('20260929000009'),
('20260929000008'),
('20260929000007'),
('20260928000006'),
('20260928000005'),
('20260928000004'),
('20260928000003'),
('20260928000002'),
('20260928000001'),
('20260928000000');
