# frozen_string_literal: true

require "test_helper"

class RuntimeAndCapacityChecksTest < Minitest::Test
  def test_solid_queue_configured_check_flags_missing_runtime
    findings = SolidLens::Checks::SolidQueueConfiguredCheck.new(
      runtime: {rails_env: "production", active_job_queue_adapter: "solid_queue"},
      queue_config: {},
      database: {},
      tables: {}
    ).call

    finding = findings.find { |item| item.id == "solid_queue.runtime.missing" }

    refute_nil finding
    assert_equal :high, finding.severity
  end

  def test_solid_queue_configured_check_flags_adapter_mismatch
    findings = SolidLens::Checks::SolidQueueConfiguredCheck.new(
      runtime: {solid_queue_version: "1.4.0", active_job_queue_adapter: "sidekiq"},
      queue_config: {},
      database: {},
      tables: {}
    ).call

    finding = findings.find { |item| item.id == "solid_queue.active_job.adapter_mismatch" }

    refute_nil finding
    assert_equal :medium, finding.severity
    assert_equal "sidekiq", finding.evidence.fetch(:active_job_queue_adapter)
  end

  def test_pool_capacity_check_matches_target_finding_shape
    findings = SolidLens::Checks::PoolCapacityCheck.new(
      queue_config: {max_worker_threads: 10, required_pool_size: 12, worker_process_count: 1, mode: "fork"},
      database: {connection_pool_size: 10},
      tables: {}
    ).call

    finding = findings.fetch(0)

    assert_equal "solid_queue.pool.undersized", finding.id
    assert_equal :high, finding.severity
    assert_equal 8, finding.evidence.fetch(:safe_worker_threads)
    assert_includes finding.recommendation, ">= 12"
  end

  def test_skip_locked_check_escalates_when_concurrency_is_present
    findings = SolidLens::Checks::DatabaseSkipLockedCheck.new(
      queue_config: {worker_thread_capacity: 3},
      database: {adapter_name: "SQLite", database_version: "3.45.0", skip_locked_supported: false},
      tables: {}
    ).call

    assert_equal :high, findings.fetch(0).severity
  end

  def test_database_connection_check_flags_unavailable_queue_db
    findings = SolidLens::Checks::DatabaseConnectionCheck.new(
      runtime: {solid_queue_connects_to: {database: {writing: :queue}}, rails_env: "production"},
      queue_config: {},
      database: {connected: false, error: "ActiveRecord connection unavailable"},
      tables: {}
    ).call

    assert_equal "solid_queue.database.unavailable", findings.fetch(0).id
    assert_equal :high, findings.fetch(0).severity
  end

  def test_queue_config_readiness_check_flags_unreadable_file
    findings = SolidLens::Checks::QueueConfigReadinessCheck.new(
      queue_config: {
        path: "/app/config/queue.yml",
        file_found: true,
        environment: "production",
        file_error: "Psych::SyntaxError: mapping values are not allowed here"
      },
      runtime: {},
      database: {},
      tables: {}
    ).call

    finding = findings.find { |item| item.id == "solid_queue.queue_config.file_unreadable" }

    refute_nil finding
    assert_equal :high, finding.severity
    assert_equal "/app/config/queue.yml", finding.evidence.fetch(:path)
  end

  def test_queue_config_readiness_check_flags_runtime_fallback
    findings = SolidLens::Checks::QueueConfigReadinessCheck.new(
      queue_config: {
        path: "/app/config/queue.yml",
        file_found: true,
        environment: "production",
        mode: "unknown",
        runtime_error: "RuntimeError: failed to build runtime config"
      },
      runtime: {},
      database: {},
      tables: {}
    ).call

    finding = findings.find { |item| item.id == "solid_queue.queue_config.runtime_unavailable" }

    refute_nil finding
    assert_equal :medium, finding.severity
    assert_equal "unknown", finding.evidence.fetch(:mode)
  end
end
