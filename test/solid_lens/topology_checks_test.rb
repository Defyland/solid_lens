# frozen_string_literal: true

require "test_helper"

class TopologyChecksTest < Minitest::Test
  def test_worker_config_check_flags_invalid_worker_settings
    findings = SolidLens::Checks::WorkerConfigCheck.new(
      queue_config: {
        mode: "fork",
        workers: [{"queues" => ["default"], "threads" => 0, "processes" => 0, "polling_interval" => 0}],
        dispatchers: []
      },
      database: {},
      tables: {}
    ).call

    invalid = findings.find { |finding| finding.id == "solid_queue.workers.invalid" }

    refute_nil invalid
    assert_equal :high, invalid.severity
    assert_includes invalid.evidence.fetch(:workers).first.fetch("issues"), "threads_must_be_positive"
    assert_includes invalid.evidence.fetch(:workers).first.fetch("issues"), "processes_must_be_positive"
    assert_includes invalid.evidence.fetch(:workers).first.fetch("issues"), "polling_interval_must_be_positive"
  end

  def test_worker_config_check_flags_invalid_dispatcher_settings
    findings = SolidLens::Checks::WorkerConfigCheck.new(
      queue_config: {
        mode: "fork",
        workers: [{"queues" => ["default"], "threads" => 3, "processes" => 1, "polling_interval" => 0.1}],
        dispatchers: [{
          "polling_interval" => 0,
          "batch_size" => 0,
          "concurrency_maintenance" => true,
          "concurrency_maintenance_interval" => 0
        }]
      },
      database: {},
      tables: {}
    ).call

    invalid = findings.find { |finding| finding.id == "solid_queue.dispatchers.invalid" }

    refute_nil invalid
    assert_equal :high, invalid.severity
    assert_includes invalid.evidence.fetch(:dispatchers).first.fetch("issues"), "polling_interval_must_be_positive"
    assert_includes invalid.evidence.fetch(:dispatchers).first.fetch("issues"), "batch_size_must_be_positive"
    assert_includes invalid.evidence.fetch(:dispatchers).first.fetch("issues"), "concurrency_maintenance_interval_must_be_positive"
  end

  def test_worker_config_check_flags_ignored_processes_in_async_mode
    findings = SolidLens::Checks::WorkerConfigCheck.new(
      queue_config: {
        mode: "async",
        workers: [{"queues" => ["default"], "threads" => 3, "processes" => 4, "polling_interval" => 0.1}],
        dispatchers: []
      },
      database: {},
      tables: {}
    ).call

    ignored = findings.find { |finding| finding.id == "solid_queue.workers.processes.ignored_async" }

    refute_nil ignored
    assert_equal :medium, ignored.severity
    assert_equal 4, ignored.evidence.fetch(:workers).first.fetch("configured_processes")
    assert_equal 1, ignored.evidence.fetch(:workers).first.fetch("effective_processes")
  end

  def test_worker_config_check_escalates_slow_dispatchers_when_jobs_are_overdue
    findings = SolidLens::Checks::WorkerConfigCheck.new(
      queue_config: {
        mode: "fork",
        workers: [{"queues" => ["default"], "threads" => 3, "processes" => 1, "polling_interval" => 0.1}],
        dispatchers: [{"polling_interval" => 10, "batch_size" => 250}]
      },
      database: {},
      tables: {overdue_scheduled_count: 2}
    ).call

    finding = findings.find { |item| item.id == "solid_queue.dispatchers.polling_interval.high" }

    refute_nil finding
    assert_equal :high, finding.severity
    assert_equal 10, finding.evidence.fetch(:dispatchers).first.fetch("polling_interval")
  end

  def test_worker_config_check_treats_invalid_dispatchers_as_missing_when_jobs_are_due
    findings = SolidLens::Checks::WorkerConfigCheck.new(
      queue_config: {
        mode: "fork",
        workers: [{"queues" => ["default"], "threads" => 3, "processes" => 1, "polling_interval" => 0.1}],
        dispatchers: [{"polling_interval" => 0, "batch_size" => 0, "concurrency_maintenance" => true, "concurrency_maintenance_interval" => 0}]
      },
      database: {},
      tables: {overdue_scheduled_count: 2}
    ).call

    finding = findings.find { |item| item.id == "solid_queue.dispatchers.none_with_due_jobs" }

    refute_nil finding
    assert_equal :high, finding.severity
    assert_equal 2, finding.evidence.fetch(:overdue_scheduled_count)
    assert_equal 1, finding.evidence.fetch(:configured_dispatcher_count)
  end

  def test_worker_config_check_ignores_concurrency_interval_when_maintenance_is_disabled
    findings = SolidLens::Checks::WorkerConfigCheck.new(
      queue_config: {
        mode: "fork",
        workers: [{"queues" => ["default"], "threads" => 3, "processes" => 1, "polling_interval" => 0.1}],
        dispatchers: [{
          "polling_interval" => 1,
          "batch_size" => 100,
          "concurrency_maintenance" => false,
          "concurrency_maintenance_interval" => 0
        }]
      },
      database: {},
      tables: {}
    ).call

    refute findings.any? { |finding| finding.id == "solid_queue.dispatchers.invalid" }
  end

  def test_scheduler_config_check_flags_invalid_scheduler_settings
    findings = SolidLens::Checks::SchedulerConfigCheck.new(
      queue_config: {
        mode: "fork",
        scheduler_count: 1,
        scheduler: {"polling_interval" => 0, "dynamic_tasks_enabled" => true}
      },
      database: {},
      tables: {}
    ).call

    invalid = findings.find { |finding| finding.id == "solid_queue.scheduler.invalid" }

    refute_nil invalid
    assert_equal :high, invalid.severity
    assert_includes invalid.evidence.fetch(:scheduler_issues), "polling_interval_must_be_positive"
  end

  def test_scheduler_config_check_escalates_slow_scheduler_when_recurring_tasks_are_overdue
    findings = SolidLens::Checks::SchedulerConfigCheck.new(
      queue_config: {
        mode: "fork",
        scheduler_count: 1,
        scheduler: {"polling_interval" => 10, "dynamic_tasks_enabled" => true}
      },
      database: {},
      tables: {
        overdue_recurring_task_count: 2,
        oldest_recurring_task_lag_seconds: 90.0
      }
    ).call

    finding = findings.find { |item| item.id == "solid_queue.scheduler.polling_interval.high" }

    refute_nil finding
    assert_equal :high, finding.severity
    assert_equal 10, finding.evidence.fetch(:scheduler).fetch("polling_interval")
    assert_equal 2, finding.evidence.fetch(:overdue_recurring_task_count)
  end

  def test_scheduler_config_check_flags_dynamic_tasks_disabled_when_dynamic_recurring_tasks_exist
    findings = SolidLens::Checks::SchedulerConfigCheck.new(
      queue_config: {
        mode: "fork",
        scheduler_count: 0,
        scheduler: {"polling_interval" => 5, "dynamic_tasks_enabled" => false}
      },
      database: {},
      tables: {
        recurring_task_count: 1,
        dynamic_recurring_task_count: 1,
        overdue_recurring_task_count: 0
      }
    ).call

    finding = findings.find { |item| item.id == "solid_queue.scheduler.dynamic_tasks.disabled" }

    refute_nil finding
    assert_equal :medium, finding.severity
    assert_equal 1, finding.evidence.fetch(:dynamic_recurring_task_count)
    assert_equal false, finding.evidence.fetch(:scheduler).fetch("dynamic_tasks_enabled")
  end

  def test_scheduler_config_check_escalates_dynamic_tasks_disabled_when_dynamic_recurring_tasks_are_overdue
    findings = SolidLens::Checks::SchedulerConfigCheck.new(
      queue_config: {
        mode: "fork",
        scheduler_count: 1,
        scheduler: {"polling_interval" => 5, "dynamic_tasks_enabled" => false}
      },
      database: {},
      tables: {
        recurring_task_count: 1,
        dynamic_recurring_task_count: 1,
        overdue_recurring_task_count: 2,
        overdue_recurring_task_keys: ["nightly_cleanup"]
      }
    ).call

    finding = findings.find { |item| item.id == "solid_queue.scheduler.dynamic_tasks.disabled" }

    refute_nil finding
    assert_equal :high, finding.severity
    assert_equal 2, finding.evidence.fetch(:overdue_recurring_task_count)
  end

  def test_scheduler_config_check_ignores_dynamic_tasks_disabled_when_no_dynamic_recurring_tasks_exist
    findings = SolidLens::Checks::SchedulerConfigCheck.new(
      queue_config: {
        mode: "fork",
        scheduler_count: 1,
        scheduler: {"polling_interval" => 5, "dynamic_tasks_enabled" => false}
      },
      database: {},
      tables: {
        recurring_task_count: 0,
        dynamic_recurring_task_count: 0,
        overdue_recurring_task_count: 0
      }
    ).call

    refute findings.any? { |finding| finding.id == "solid_queue.scheduler.dynamic_tasks.disabled" }
  end
end
