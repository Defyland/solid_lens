# frozen_string_literal: true

require "test_helper"

class SchemaAndPlanChecksTest < Minitest::Test
  def test_schema_readiness_check_flags_missing_tables
    findings = SolidLens::Checks::SchemaReadinessCheck.new(
      runtime: {},
      queue_config: {},
      database: {connected: true},
      tables: {
        available: true,
        existing_tables: ["solid_queue_jobs"],
        missing_tables: ["solid_queue_ready_executions"]
      }
    ).call

    assert_equal "solid_queue.schema.incomplete", findings.fetch(0).id
  end

  def test_critical_indexes_check_flags_missing_poll_index
    findings = SolidLens::Checks::CriticalIndexesCheck.new(
      runtime: {},
      queue_config: {},
      database: {},
      tables: {
        available: true,
        existing_tables: ["solid_queue_ready_executions"],
        indexes: {"solid_queue_ready_executions" => ["index_solid_queue_poll_all"]}
      }
    ).call

    assert_equal "solid_queue.indexes.missing", findings.fetch(0).id
  end

  def test_critical_indexes_check_flags_missing_blocked_execution_maintenance_index
    findings = SolidLens::Checks::CriticalIndexesCheck.new(
      runtime: {},
      queue_config: {},
      database: {},
      tables: {
        available: true,
        existing_tables: ["solid_queue_blocked_executions"],
        indexes: {"solid_queue_blocked_executions" => ["index_solid_queue_blocked_executions_for_release"]}
      }
    ).call

    assert_equal "solid_queue.indexes.missing", findings.fetch(0).id
    assert_equal ["index_solid_queue_blocked_executions_for_maintenance"], findings.fetch(0).evidence.fetch("solid_queue_blocked_executions").fetch(:missing_indexes)
  end

  def test_critical_indexes_check_flags_missing_semaphore_cleanup_index
    findings = SolidLens::Checks::CriticalIndexesCheck.new(
      runtime: {},
      queue_config: {},
      database: {},
      tables: {
        available: true,
        existing_tables: ["solid_queue_semaphores"],
        indexes: {"solid_queue_semaphores" => ["index_solid_queue_semaphores_on_key"]}
      }
    ).call

    assert_equal "solid_queue.indexes.missing", findings.fetch(0).id
    assert_equal ["index_solid_queue_semaphores_on_expires_at"], findings.fetch(0).evidence.fetch("solid_queue_semaphores").fetch(:missing_indexes)
  end

  def test_explain_check_flags_risky_query_plan
    findings = SolidLens::Checks::ExplainCheck.new(
      queue_config: {},
      database: {},
      tables: {
        explains: {
          poll_all: {
            adapter: "sqlite",
            expected_indexes: ["index_solid_queue_poll_all"],
            rows: [{"detail" => "SCAN solid_queue_ready_executions"}]
          }
        }
      }
    ).call

    finding = findings.fetch(0)

    assert_equal "solid_queue.explain.bad_plan", finding.id
    assert_equal :high, finding.severity
    assert_equal ["full_scan"], finding.evidence.fetch(:poll_all).fetch(:analysis).fetch(:reasons)
  end

  def test_explain_check_ignores_safe_query_plan
    findings = SolidLens::Checks::ExplainCheck.new(
      queue_config: {},
      database: {},
      tables: {
        explains: {
          poll_all: {
            adapter: "sqlite",
            expected_indexes: ["index_solid_queue_poll_all"],
            rows: [{"detail" => "SEARCH solid_queue_ready_executions USING INDEX index_solid_queue_poll_all"}]
          }
        }
      }
    ).call

    assert_empty findings
  end

  def test_explain_check_flags_explain_errors
    findings = SolidLens::Checks::ExplainCheck.new(
      queue_config: {},
      database: {},
      tables: {
        explains: {
          poll_all: {
            adapter: "sqlite",
            expected_indexes: ["index_solid_queue_poll_all"],
            error: "SQLite3::SQLException: no such table"
          }
        }
      }
    ).call

    finding = findings.fetch(0)

    assert_equal "solid_queue.explain.bad_plan", finding.id
    assert_equal ["explain_error"], finding.evidence.fetch(:poll_all).fetch(:analysis).fetch(:reasons)
  end
end
