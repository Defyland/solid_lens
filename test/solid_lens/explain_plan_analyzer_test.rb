# frozen_string_literal: true

require "test_helper"

class ExplainPlanAnalyzerTest < Minitest::Test
  def test_sqlite_plan_flags_full_scan
    explains = {
      poll_all: {
        adapter: "sqlite",
        expected_indexes: ["index_solid_queue_poll_all"],
        rows: [{"detail" => "SCAN solid_queue_ready_executions"}]
      }
    }

    risky = SolidLens::Analyzers::ExplainPlanAnalyzer.new(explains).risky_queries

    assert_equal ["full_scan"], risky.fetch(:poll_all).fetch(:analysis).fetch(:reasons)
  end

  def test_mysql_plan_flags_missing_key_and_filesort
    explains = {
      poll_by_queue: {
        adapter: "mysql2",
        expected_indexes: ["index_solid_queue_poll_by_queue"],
        rows: [{"type" => "ALL", "key" => nil, "Extra" => "Using filesort"}]
      }
    }

    risky = SolidLens::Analyzers::ExplainPlanAnalyzer.new(explains).risky_queries

    assert_includes risky.fetch(:poll_by_queue).fetch(:analysis).fetch(:reasons), "full_table_scan"
    assert_includes risky.fetch(:poll_by_queue).fetch(:analysis).fetch(:reasons), "filesort"
    assert_includes risky.fetch(:poll_by_queue).fetch(:analysis).fetch(:reasons), "expected_index_missing"
  end

  def test_postgres_json_plan_flags_seq_scan
    explains = {
      dispatch_due: {
        adapter: "postgresql",
        expected_indexes: ["index_solid_queue_dispatch_all"],
        rows: [{
          "QUERY PLAN" => [
            {
              "Plan" => {
                "Node Type" => "Seq Scan",
                "Relation Name" => "solid_queue_scheduled_executions"
              }
            }
          ]
        }]
      }
    }

    risky = SolidLens::Analyzers::ExplainPlanAnalyzer.new(explains).risky_queries

    assert_includes risky.fetch(:dispatch_due).fetch(:analysis).fetch(:reasons), "seq_scan"
  end
end
