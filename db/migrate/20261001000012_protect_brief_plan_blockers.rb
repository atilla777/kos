class ProtectBriefPlanBlockers < ActiveRecord::Migration[8.1]
  def up
    %w[DELETE UPDATE].each do |operation|
      execute <<~SQL
        CREATE TRIGGER protect_brief_plan_blocker_#{operation.downcase}
        BEFORE #{operation} ON task_dependencies
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
      SQL
    end
  end

  def down
    %w[delete update].each { |operation| execute "DROP TRIGGER protect_brief_plan_blocker_#{operation}" }
  end
end
