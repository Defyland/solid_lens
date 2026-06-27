# frozen_string_literal: true

require "tempfile"
require "test_helper"

class DoctorIntegrationTest < SolidLensIntegrationCase
  def test_queue_config_collector_uses_runtime_configuration
    config = SolidLens::Collectors::QueueConfigCollector.new.collect

    assert_equal "test", config.fetch(:environment)
    assert_equal 8, config.fetch(:worker_thread_capacity)
    assert_equal 4, config.fetch(:max_worker_threads)
    assert_equal 6, config.fetch(:required_pool_size)
    assert_equal 2, config.fetch(:worker_process_count)
    assert_equal 1, config.fetch(:dispatcher_count)
    assert_equal 1, config.fetch(:scheduler_count)
    assert_equal ["mailers*"], config.fetch(:wildcard_queue_specs)
    assert_equal({"polling_interval" => 5, "dynamic_tasks_enabled" => true}, config.fetch(:scheduler))
    scheduler_process = config.fetch(:configured_processes).find { |process| process.fetch("kind") == "scheduler" }
    assert_equal 5, scheduler_process.fetch("attributes").fetch("polling_interval")
  end

  def test_runner_doctor_reports_real_pool_pressure_against_solid_queue_defaults
    report = SolidLens::Runner.new.doctor
    finding = report.findings.find { |item| item.id == "solid_queue.pool.undersized" }

    refute_nil finding
    assert_equal 4, finding.evidence.fetch(:worker_threads)
    assert_equal 5, finding.evidence.fetch(:queue_db_pool)
    assert_equal 6, finding.evidence.fetch(:required_pool_size)
  end

  def test_claimed_execution_check_uses_solid_queue_alive_threshold
    SolidQueue.process_alive_threshold = 30.seconds
    create_stale_claimed_execution(last_heartbeat_at: 31.seconds.ago)

    report = SolidLens::Runner.new.doctor
    finding = report.findings.find { |item| item.id == "solid_queue.claimed.dead_process" }

    refute_nil finding
    assert_equal 1, finding.evidence.fetch(:claimed_by_dead_process_count)
    assert finding.evidence.fetch(:oldest_claimed_dead_lag_seconds) >= 31.0
  end

  def test_runner_doctor_flags_missing_critical_index
    ActiveRecord::Base.connection.remove_index(:solid_queue_ready_executions, name: "index_solid_queue_poll_by_queue")

    report = SolidLens::Runner.new.doctor
    finding = report.findings.find { |item| item.id == "solid_queue.indexes.missing" }

    refute_nil finding
    assert_equal ["index_solid_queue_poll_by_queue"], finding.evidence.fetch("solid_queue_ready_executions").fetch(:missing_indexes)
  end

  def test_runner_doctor_flags_incomplete_schema
    ActiveRecord::Base.connection.drop_table(:solid_queue_pauses)

    report = SolidLens::Runner.new.doctor
    finding = report.findings.find { |item| item.id == "solid_queue.schema.incomplete" }

    refute_nil finding
    assert_includes finding.evidence.fetch(:missing_tables), "solid_queue_pauses"
  end

  def test_runner_doctor_flags_processes_ignored_in_async_mode
    async_queue = SolidLens::TestSupport::RailsIntegration::APP_ROOT.join("config/queue_async.yml").to_s

    report = SolidLens::TestSupport::RailsIntegration.with_env(
      "SOLID_QUEUE_CONFIG" => async_queue,
      "SOLID_QUEUE_SUPERVISOR_MODE" => "async"
    ) do
      SolidLens::Runner.new.doctor
    end

    finding = report.findings.find { |item| item.id == "solid_queue.workers.processes.ignored_async" }

    refute_nil finding
    assert_equal "async", finding.evidence.fetch(:mode)
    assert_equal 3, finding.evidence.fetch(:workers).first.fetch("configured_processes")
  end

  def test_runner_doctor_flags_invalid_dispatcher_configuration
    invalid_queue = Tempfile.new(["queue", ".yml"])
    invalid_queue.write(<<~YAML)
      test:
        workers:
          - queues:
              - default
            threads: 3
            processes: 1
        dispatchers:
          - polling_interval: 0
            batch_size: 0
            concurrency_maintenance: true
            concurrency_maintenance_interval: 0
    YAML
    invalid_queue.flush

    report = SolidLens::TestSupport::RailsIntegration.with_env("SOLID_QUEUE_CONFIG" => invalid_queue.path) do
      SolidLens::Runner.new.doctor
    end
    finding = report.findings.find { |item| item.id == "solid_queue.dispatchers.invalid" }

    refute_nil finding
    assert_includes finding.evidence.fetch(:dispatchers).first.fetch("issues"), "polling_interval_must_be_positive"
    assert_includes finding.evidence.fetch(:dispatchers).first.fetch("issues"), "batch_size_must_be_positive"
    assert_includes finding.evidence.fetch(:dispatchers).first.fetch("issues"), "concurrency_maintenance_interval_must_be_positive"
  ensure
    invalid_queue&.close
  end

  def test_runner_doctor_flags_invalid_scheduler_configuration
    invalid_queue = Tempfile.new(["queue", ".yml"])
    invalid_queue.write(<<~YAML)
      test:
        workers:
          - queues:
              - default
            threads: 3
            processes: 1
        dispatchers:
          - polling_interval: 1
            batch_size: 500
        scheduler:
          polling_interval: 0
          dynamic_tasks_enabled: true
    YAML
    invalid_queue.flush

    report = SolidLens::TestSupport::RailsIntegration.with_env("SOLID_QUEUE_CONFIG" => invalid_queue.path) do
      SolidLens::Runner.new.doctor
    end
    finding = report.findings.find { |item| item.id == "solid_queue.scheduler.invalid" }

    refute_nil finding
    assert_includes finding.evidence.fetch(:scheduler_issues), "polling_interval_must_be_positive"
  ensure
    invalid_queue&.close
  end

  def test_runner_doctor_flags_dynamic_tasks_disabled_when_dynamic_recurring_tasks_exist
    scheduler_queue = Tempfile.new(["queue", ".yml"])
    scheduler_queue.write(<<~YAML)
      test:
        workers:
          - queues:
              - default
            threads: 3
            processes: 1
        dispatchers:
          - polling_interval: 1
            batch_size: 500
        scheduler:
          polling_interval: 5
          dynamic_tasks_enabled: false
    YAML
    scheduler_queue.flush
    create_dynamic_recurring_task(
      key: "nightly_cleanup",
      schedule: "* * * * *",
      created_at: Time.current
    )

    report = SolidLens::TestSupport::RailsIntegration.with_env("SOLID_QUEUE_CONFIG" => scheduler_queue.path) do
      SolidLens::Runner.new.doctor
    end
    finding = report.findings.find { |item| item.id == "solid_queue.scheduler.dynamic_tasks.disabled" }

    refute_nil finding
    assert_equal :medium, finding.severity
    assert_equal 1, finding.evidence.fetch(:dynamic_recurring_task_count)
    assert_equal false, finding.evidence.fetch(:scheduler).fetch("dynamic_tasks_enabled")
  ensure
    scheduler_queue&.close
  end

  def test_runner_doctor_treats_invalid_dispatchers_as_missing_when_scheduled_jobs_are_due
    invalid_queue = Tempfile.new(["queue", ".yml"])
    invalid_queue.write(<<~YAML)
      test:
        workers:
          - queues:
              - default
            threads: 3
            processes: 1
        dispatchers:
          - polling_interval: 0
            batch_size: 0
            concurrency_maintenance: true
            concurrency_maintenance_interval: 0
    YAML
    invalid_queue.flush
    create_scheduled_execution(queue_name: "default", scheduled_at: 2.minutes.ago)

    report = SolidLens::TestSupport::RailsIntegration.with_env("SOLID_QUEUE_CONFIG" => invalid_queue.path) do
      SolidLens::Runner.new.doctor
    end
    finding = report.findings.find { |item| item.id == "solid_queue.dispatchers.none_with_due_jobs" }

    refute_nil finding
    assert_equal 1, finding.evidence.fetch(:configured_dispatcher_count)
    assert_equal 1, finding.evidence.fetch(:overdue_scheduled_count)
  ensure
    invalid_queue&.close
  end

  def test_runner_doctor_flags_unreadable_queue_config_file
    invalid_queue = Tempfile.new(["queue", ".yml"])
    invalid_queue.write(<<~YAML)
      test:
        workers: [
    YAML
    invalid_queue.flush

    report = SolidLens::TestSupport::RailsIntegration.with_env("SOLID_QUEUE_CONFIG" => invalid_queue.path) do
      SolidLens::Runner.new.doctor
    end
    finding = report.findings.find { |item| item.id == "solid_queue.queue_config.file_unreadable" }

    refute_nil finding
    assert_equal invalid_queue.path, finding.evidence.fetch(:path)
    assert_match(/Psych::SyntaxError/, finding.evidence.fetch(:file_error))
  ensure
    invalid_queue&.close
  end

  def test_runner_doctor_flags_expired_blocked_jobs_older_than_maintenance_interval
    create_blocked_execution(
      queue_name: "critical",
      concurrency_key: "account:42",
      created_at: 20.minutes.ago,
      expires_at: 601.seconds.ago
    )

    report = SolidLens::Runner.new.doctor
    finding = report.findings.find { |item| item.id == "solid_queue.blocked.expired_longer_than_maintenance_interval" }

    refute_nil finding
    assert_equal 1, finding.evidence.fetch(:expired_blocked_execution_count)
    assert_equal({"critical" => 1}, finding.evidence.fetch(:blocked_queue_depth_by_queue))
    assert_equal 600.0, finding.evidence.fetch(:fastest_concurrency_maintenance_interval_seconds)
  end

  def test_runner_doctor_flags_expired_semaphores_older_than_maintenance_interval
    create_semaphore(
      key: "account:77",
      value: 0,
      expires_at: 601.seconds.ago,
      created_at: 20.minutes.ago
    )

    report = SolidLens::Runner.new.doctor
    finding = report.findings.find { |item| item.id == "solid_queue.semaphores.expired_longer_than_maintenance_interval" }

    refute_nil finding
    assert_equal 1, finding.evidence.fetch(:expired_semaphore_count)
    assert_equal 600.0, finding.evidence.fetch(:fastest_concurrency_maintenance_interval_seconds)
  end

  def test_runner_doctor_flags_expired_orphan_semaphores_without_blocked_backlog
    create_semaphore(
      key: "account:88",
      value: 0,
      expires_at: 5.minutes.ago,
      created_at: 20.minutes.ago
    )

    report = SolidLens::Runner.new.doctor
    finding = report.findings.find { |item| item.id == "solid_queue.semaphores.expired_without_blocked_backlog" }

    refute_nil finding
    assert_equal 1, finding.evidence.fetch(:expired_orphan_semaphore_count)
    assert_equal ["account:88"], finding.evidence.fetch(:expired_orphan_semaphore_keys)
    assert finding.evidence.fetch(:oldest_expired_orphan_semaphore_lag_seconds) >= 300.0
  end

  def test_runner_doctor_flags_overdue_recurring_tasks
    create_dynamic_recurring_task(
      key: "nightly_cleanup",
      schedule: "* * * * *",
      created_at: 3.minutes.ago
    )

    report = SolidLens::Runner.new.doctor
    finding = report.findings.find { |item| item.id == "solid_queue.recurring.overdue" }

    refute_nil finding
    assert_equal 1, finding.evidence.fetch(:overdue_recurring_task_count)
    assert_includes finding.evidence.fetch(:overdue_recurring_task_keys), "nightly_cleanup"
  end

  def test_runner_doctor_flags_missing_scheduler_when_overdue_recurring_tasks_exist
    create_dynamic_recurring_task(
      key: "nightly_cleanup",
      schedule: "* * * * *",
      created_at: 3.minutes.ago
    )

    report = SolidLens::TestSupport::RailsIntegration.with_env("SOLID_QUEUE_SKIP_RECURRING" => "1") do
      SolidLens::Runner.new.doctor
    end
    finding = report.findings.find { |item| item.id == "solid_queue.scheduler.none_with_overdue_recurring_tasks" }

    refute_nil finding
    assert_equal 0, finding.evidence.fetch(:scheduler_count)
    assert_equal true, finding.evidence.fetch(:scheduler).fetch("dynamic_tasks_enabled")
  end

  def test_runner_doctor_treats_unusable_scheduler_as_missing_when_overdue_recurring_tasks_exist
    invalid_queue = Tempfile.new(["queue", ".yml"])
    invalid_queue.write(<<~YAML)
      test:
        workers:
          - queues:
              - default
            threads: 3
            processes: 1
        dispatchers:
          - polling_interval: 1
            batch_size: 500
        scheduler:
          polling_interval: 0
          dynamic_tasks_enabled: true
    YAML
    invalid_queue.flush
    create_dynamic_recurring_task(
      key: "nightly_cleanup",
      schedule: "* * * * *",
      created_at: 3.minutes.ago
    )

    report = SolidLens::TestSupport::RailsIntegration.with_env("SOLID_QUEUE_CONFIG" => invalid_queue.path) do
      SolidLens::Runner.new.doctor
    end
    finding = report.findings.find { |item| item.id == "solid_queue.scheduler.none_with_overdue_recurring_tasks" }

    refute_nil finding
    assert_equal 1, finding.evidence.fetch(:scheduler_count)
    assert_includes finding.evidence.fetch(:scheduler_issues), "polling_interval_must_be_positive"
  ensure
    invalid_queue&.close
  end

  def test_runner_doctor_does_not_blame_dynamic_tasks_disabled_as_scheduler_issue_for_static_overdue_tasks
    scheduler_queue = Tempfile.new(["queue", ".yml"])
    scheduler_queue.write(<<~YAML)
      test:
        workers:
          - queues:
              - default
            threads: 3
            processes: 1
        dispatchers:
          - polling_interval: 1
            batch_size: 500
        scheduler:
          polling_interval: 5
          dynamic_tasks_enabled: false
    YAML
    scheduler_queue.flush
    create_static_recurring_task(
      key: "static_cleanup",
      schedule: "* * * * *",
      created_at: 3.minutes.ago
    )
    create_dynamic_recurring_task(
      key: "dynamic_cleanup",
      schedule: "0 * * * *",
      created_at: Time.current
    )

    report = SolidLens::TestSupport::RailsIntegration.with_env("SOLID_QUEUE_CONFIG" => scheduler_queue.path) do
      SolidLens::Runner.new.doctor
    end

    assert report.findings.any? { |item| item.id == "solid_queue.recurring.overdue" }
    assert report.findings.any? { |item| item.id == "solid_queue.scheduler.dynamic_tasks.disabled" }
    finding = report.findings.find { |item| item.id == "solid_queue.scheduler.none_with_overdue_recurring_tasks" }

    refute_nil finding
    assert_includes finding.evidence.fetch(:scheduler_issues), "scheduler_process_missing"
    refute_includes finding.evidence.fetch(:scheduler_issues), "dynamic_tasks_disabled"
  ensure
    scheduler_queue&.close
  end

  def test_runner_doctor_escalates_slow_scheduler_when_overdue_recurring_tasks_exist
    slow_queue = Tempfile.new(["queue", ".yml"])
    slow_queue.write(<<~YAML)
      test:
        workers:
          - queues:
              - default
            threads: 3
            processes: 1
        dispatchers:
          - polling_interval: 1
            batch_size: 500
        scheduler:
          polling_interval: 10
          dynamic_tasks_enabled: true
    YAML
    slow_queue.flush
    create_dynamic_recurring_task(
      key: "nightly_cleanup",
      schedule: "* * * * *",
      created_at: 3.minutes.ago
    )

    report = SolidLens::TestSupport::RailsIntegration.with_env("SOLID_QUEUE_CONFIG" => slow_queue.path) do
      SolidLens::Runner.new.doctor
    end
    finding = report.findings.find { |item| item.id == "solid_queue.scheduler.polling_interval.high" }

    refute_nil finding
    assert_equal :high, finding.severity
    assert_equal 1, finding.evidence.fetch(:overdue_recurring_task_count)
    assert_equal 10, finding.evidence.fetch(:scheduler).fetch("polling_interval")
  ensure
    slow_queue&.close
  end
end
