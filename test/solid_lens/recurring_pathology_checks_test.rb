# frozen_string_literal: true

require "test_helper"

class RecurringPathologyChecksTest < Minitest::Test
  def test_recurring_tasks_check_flags_overdue_recurring_tasks
    findings = SolidLens::Checks::RecurringTasksCheck.new(
      queue_config: {scheduler_count: 1},
      database: {},
      tables: {
        recurring_task_count: 1,
        dynamic_recurring_task_count: 1,
        overdue_recurring_task_count: 1,
        overdue_dynamic_recurring_task_count: 1,
        overdue_static_recurring_task_count: 0,
        oldest_recurring_task_lag_seconds: 90.0,
        overdue_recurring_task_keys: ["nightly_cleanup"],
        overdue_recurring_tasks: [{key: "nightly_cleanup", lag_seconds: 90.0}]
      }
    ).call

    finding = findings.find { |item| item.id == "solid_queue.recurring.overdue" }

    refute_nil finding
    assert_equal :high, finding.severity
    assert_equal ["nightly_cleanup"], finding.evidence.fetch(:overdue_recurring_task_keys)
  end

  def test_recurring_tasks_check_flags_missing_scheduler_when_recurring_tasks_are_overdue
    findings = SolidLens::Checks::RecurringTasksCheck.new(
      queue_config: {
        mode: "fork",
        scheduler_count: 0,
        scheduler: {"polling_interval" => 5, "dynamic_tasks_enabled" => true}
      },
      database: {},
      tables: {
        recurring_task_count: 1,
        dynamic_recurring_task_count: 1,
        overdue_recurring_task_count: 1,
        overdue_dynamic_recurring_task_count: 1,
        overdue_static_recurring_task_count: 0,
        oldest_recurring_task_lag_seconds: 90.0,
        overdue_recurring_task_keys: ["nightly_cleanup"],
        overdue_recurring_tasks: [{key: "nightly_cleanup", lag_seconds: 90.0}]
      }
    ).call

    finding = findings.find { |item| item.id == "solid_queue.scheduler.none_with_overdue_recurring_tasks" }

    refute_nil finding
    assert_equal :high, finding.severity
    assert_equal 0, finding.evidence.fetch(:scheduler_count)
    assert_equal true, finding.evidence.fetch(:scheduler).fetch("dynamic_tasks_enabled")
    assert_includes finding.evidence.fetch(:scheduler_issues), "scheduler_process_missing"
  end

  def test_recurring_tasks_check_treats_unusable_scheduler_as_missing_when_recurring_tasks_are_overdue
    findings = SolidLens::Checks::RecurringTasksCheck.new(
      queue_config: {
        mode: "fork",
        scheduler_count: 1,
        scheduler: {"polling_interval" => 0, "dynamic_tasks_enabled" => false}
      },
      database: {},
      tables: {
        recurring_task_count: 1,
        dynamic_recurring_task_count: 1,
        overdue_recurring_task_count: 1,
        overdue_dynamic_recurring_task_count: 1,
        overdue_static_recurring_task_count: 0,
        oldest_recurring_task_lag_seconds: 90.0,
        overdue_recurring_task_keys: ["nightly_cleanup"],
        overdue_recurring_tasks: [{key: "nightly_cleanup", static: false, lag_seconds: 90.0}]
      }
    ).call

    finding = findings.find { |item| item.id == "solid_queue.scheduler.none_with_overdue_recurring_tasks" }

    refute_nil finding
    assert_equal 1, finding.evidence.fetch(:scheduler_count)
    assert_includes finding.evidence.fetch(:scheduler_issues), "polling_interval_must_be_positive"
    assert_includes finding.evidence.fetch(:scheduler_issues), "dynamic_tasks_disabled"
  end

  def test_recurring_tasks_check_does_not_blame_dynamic_tasks_disabled_as_scheduler_issue_for_static_overdue_tasks
    findings = SolidLens::Checks::RecurringTasksCheck.new(
      queue_config: {
        mode: "fork",
        scheduler_count: 0,
        scheduler: {"polling_interval" => 5, "dynamic_tasks_enabled" => false}
      },
      database: {},
      tables: {
        recurring_task_count: 2,
        dynamic_recurring_task_count: 1,
        overdue_recurring_task_count: 1,
        overdue_dynamic_recurring_task_count: 0,
        overdue_static_recurring_task_count: 1,
        oldest_recurring_task_lag_seconds: 90.0,
        overdue_recurring_task_keys: ["static_cleanup"],
        overdue_recurring_tasks: [{key: "static_cleanup", static: true, lag_seconds: 90.0}]
      }
    ).call

    assert findings.any? { |item| item.id == "solid_queue.recurring.overdue" }
    finding = findings.find { |item| item.id == "solid_queue.scheduler.none_with_overdue_recurring_tasks" }

    refute_nil finding
    assert_includes finding.evidence.fetch(:scheduler_issues), "scheduler_process_missing"
    refute_includes finding.evidence.fetch(:scheduler_issues), "dynamic_tasks_disabled"
  end

  def test_recurring_tasks_check_returns_no_findings_without_overdue_tasks
    findings = SolidLens::Checks::RecurringTasksCheck.new(
      queue_config: {scheduler_count: 1},
      database: {},
      tables: {
        recurring_task_count: 1,
        dynamic_recurring_task_count: 1,
        overdue_recurring_task_count: 0,
        oldest_recurring_task_lag_seconds: 0.0,
        overdue_recurring_task_keys: [],
        overdue_recurring_tasks: []
      }
    ).call

    assert_empty findings
  end
end
