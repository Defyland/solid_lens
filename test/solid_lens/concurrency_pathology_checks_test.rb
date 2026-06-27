# frozen_string_literal: true

require "test_helper"

class ConcurrencyPathologyChecksTest < Minitest::Test
  def test_claimed_executions_check_flags_dead_processes
    findings = SolidLens::Checks::ClaimedExecutionsCheck.new(
      queue_config: {},
      database: {},
      tables: {
        claimed_by_dead_process_count: 1,
        oldest_claimed_dead_lag_seconds: 45.0,
        process_alive_threshold_seconds: 30
      }
    ).call

    assert_equal :high, findings.fetch(0).severity
    assert_equal 45.0, findings.fetch(0).evidence.fetch(:oldest_claimed_dead_lag_seconds)
  end

  def test_blocked_executions_check_flags_expired_backlog_without_maintenance
    findings = SolidLens::Checks::BlockedExecutionsCheck.new(
      queue_config: {
        dispatchers: [{"polling_interval" => 1, "concurrency_maintenance" => false, "concurrency_maintenance_interval" => 600}]
      },
      tables: {
        counts: {"solid_queue_blocked_executions" => 2},
        blocked_queue_depth_by_queue: {"critical" => 2},
        oldest_blocked_age_seconds: 300.0,
        expired_blocked_execution_count: 2,
        oldest_expired_blocked_lag_seconds: 120.0
      }
    ).call

    finding = findings.fetch(0)

    assert_equal "solid_queue.blocked.expired_without_maintenance", finding.id
    assert_equal :high, finding.severity
    assert_equal 2, finding.evidence.fetch(:expired_blocked_execution_count)
  end

  def test_blocked_executions_check_flags_expired_backlog_older_than_maintenance_interval
    findings = SolidLens::Checks::BlockedExecutionsCheck.new(
      queue_config: {
        dispatchers: [{"polling_interval" => 1, "concurrency_maintenance" => true, "concurrency_maintenance_interval" => 60}]
      },
      tables: {
        counts: {"solid_queue_blocked_executions" => 1},
        blocked_queue_depth_by_queue: {"critical" => 1},
        oldest_blocked_age_seconds: 180.0,
        expired_blocked_execution_count: 1,
        oldest_expired_blocked_lag_seconds: 61.0
      }
    ).call

    finding = findings.fetch(0)

    assert_equal "solid_queue.blocked.expired_longer_than_maintenance_interval", finding.id
    assert_equal :high, finding.severity
    assert_equal 60.0, finding.evidence.fetch(:fastest_concurrency_maintenance_interval_seconds)
  end

  def test_blocked_executions_check_ignores_dispatchers_with_invalid_maintenance_path
    findings = SolidLens::Checks::BlockedExecutionsCheck.new(
      queue_config: {
        dispatchers: [{"polling_interval" => 0, "concurrency_maintenance" => true, "concurrency_maintenance_interval" => 0}]
      },
      tables: {
        counts: {"solid_queue_blocked_executions" => 1},
        blocked_queue_depth_by_queue: {"critical" => 1},
        oldest_blocked_age_seconds: 180.0,
        expired_blocked_execution_count: 1,
        oldest_expired_blocked_lag_seconds: 61.0
      }
    ).call

    finding = findings.fetch(0)

    assert_equal "solid_queue.blocked.expired_without_maintenance", finding.id
    assert_equal [{"polling_interval" => 0, "concurrency_maintenance" => true, "concurrency_maintenance_interval" => 0}], finding.evidence.fetch(:dispatchers)
  end

  def test_semaphore_health_check_flags_expired_semaphores_without_maintenance
    findings = SolidLens::Checks::SemaphoreHealthCheck.new(
      queue_config: {
        dispatchers: [{"polling_interval" => 1, "concurrency_maintenance" => false, "concurrency_maintenance_interval" => 600}]
      },
      tables: {
        counts: {
          "solid_queue_semaphores" => 2,
          "solid_queue_blocked_executions" => 1
        },
        expired_semaphore_count: 2,
        oldest_expired_semaphore_lag_seconds: 120.0
      }
    ).call

    finding = findings.fetch(0)

    assert_equal "solid_queue.semaphores.expired_without_maintenance", finding.id
    assert_equal :high, finding.severity
    assert_equal 2, finding.evidence.fetch(:expired_semaphore_count)
  end

  def test_semaphore_health_check_flags_expired_semaphores_older_than_maintenance_interval
    findings = SolidLens::Checks::SemaphoreHealthCheck.new(
      queue_config: {
        dispatchers: [{"polling_interval" => 1, "concurrency_maintenance" => true, "concurrency_maintenance_interval" => 60}]
      },
      tables: {
        counts: {
          "solid_queue_semaphores" => 1,
          "solid_queue_blocked_executions" => 0
        },
        expired_semaphore_count: 1,
        oldest_expired_semaphore_lag_seconds: 61.0
      }
    ).call

    finding = findings.fetch(0)

    assert_equal "solid_queue.semaphores.expired_longer_than_maintenance_interval", finding.id
    assert_equal :high, finding.severity
    assert_equal 60.0, finding.evidence.fetch(:fastest_concurrency_maintenance_interval_seconds)
  end

  def test_semaphore_health_check_ignores_dispatchers_with_invalid_maintenance_path
    findings = SolidLens::Checks::SemaphoreHealthCheck.new(
      queue_config: {
        dispatchers: [{"polling_interval" => 0, "concurrency_maintenance" => true, "concurrency_maintenance_interval" => 0}]
      },
      tables: {
        counts: {
          "solid_queue_semaphores" => 1,
          "solid_queue_blocked_executions" => 0
        },
        expired_semaphore_count: 1,
        oldest_expired_semaphore_lag_seconds: 61.0
      }
    ).call

    finding = findings.fetch(0)

    assert_equal "solid_queue.semaphores.expired_without_maintenance", finding.id
    assert_equal [{"polling_interval" => 0, "concurrency_maintenance" => true, "concurrency_maintenance_interval" => 0}], finding.evidence.fetch(:dispatchers)
  end

  def test_semaphore_health_check_flags_expired_orphan_semaphores_without_blocked_backlog
    findings = SolidLens::Checks::SemaphoreHealthCheck.new(
      queue_config: {
        dispatchers: [{"polling_interval" => 1, "concurrency_maintenance" => true, "concurrency_maintenance_interval" => 600}]
      },
      tables: {
        counts: {
          "solid_queue_semaphores" => 1,
          "solid_queue_blocked_executions" => 0
        },
        expired_semaphore_count: 1,
        oldest_expired_semaphore_lag_seconds: 120.0,
        expired_orphan_semaphore_count: 1,
        oldest_expired_orphan_semaphore_lag_seconds: 120.0,
        expired_orphan_semaphore_keys: ["account:77"]
      }
    ).call

    finding = findings.find { |item| item.id == "solid_queue.semaphores.expired_without_blocked_backlog" }

    refute_nil finding
    assert_equal :medium, finding.severity
    assert_equal 1, finding.evidence.fetch(:expired_orphan_semaphore_count)
    assert_equal ["account:77"], finding.evidence.fetch(:expired_orphan_semaphore_keys)
  end

  def test_semaphore_health_check_escalates_orphan_semaphores_for_high_count
    findings = SolidLens::Checks::SemaphoreHealthCheck.new(
      queue_config: {
        dispatchers: [{"polling_interval" => 1, "concurrency_maintenance" => true, "concurrency_maintenance_interval" => 600}]
      },
      tables: {
        counts: {
          "solid_queue_semaphores" => 5,
          "solid_queue_blocked_executions" => 0
        },
        expired_semaphore_count: 5,
        oldest_expired_semaphore_lag_seconds: 120.0,
        expired_orphan_semaphore_count: 5,
        oldest_expired_orphan_semaphore_lag_seconds: 120.0,
        expired_orphan_semaphore_keys: ["account:77"]
      }
    ).call

    finding = findings.find { |item| item.id == "solid_queue.semaphores.expired_without_blocked_backlog" }

    refute_nil finding
    assert_equal :high, finding.severity
  end

  def test_semaphore_health_check_escalates_orphan_semaphores_for_high_lag
    findings = SolidLens::Checks::SemaphoreHealthCheck.new(
      queue_config: {
        dispatchers: [{"polling_interval" => 1, "concurrency_maintenance" => true, "concurrency_maintenance_interval" => 600}]
      },
      tables: {
        counts: {
          "solid_queue_semaphores" => 1,
          "solid_queue_blocked_executions" => 0
        },
        expired_semaphore_count: 1,
        oldest_expired_semaphore_lag_seconds: 120.0,
        expired_orphan_semaphore_count: 1,
        oldest_expired_orphan_semaphore_lag_seconds: 300.0,
        expired_orphan_semaphore_keys: ["account:77"]
      }
    ).call

    finding = findings.find { |item| item.id == "solid_queue.semaphores.expired_without_blocked_backlog" }

    refute_nil finding
    assert_equal :high, finding.severity
  end
end
