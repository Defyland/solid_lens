# frozen_string_literal: true

require "test_helper"

class StoragePathologyChecksTest < Minitest::Test
  def test_table_bloat_check_flags_bloated_tables
    findings = SolidLens::Checks::TableBloatCheck.new(
      queue_config: {},
      database: {},
      tables: {
        bloat: {
          "solid_queue_ready_executions" => {dead_tuples: 1_500, dead_tuple_ratio: 0.3},
          "solid_queue_jobs" => {dead_tuples: 500, dead_tuple_ratio: 0.5}
        }
      }
    ).call

    finding = findings.fetch(0)

    assert_equal "solid_queue.tables.bloat", finding.id
    assert_equal :medium, finding.severity
    assert_equal 1_500, finding.evidence.fetch("solid_queue_ready_executions").fetch(:dead_tuples)
    refute finding.evidence.key?("solid_queue_jobs")
  end

  def test_table_bloat_check_ignores_bloat_errors
    findings = SolidLens::Checks::TableBloatCheck.new(
      queue_config: {},
      database: {},
      tables: {bloat: {error: "PG stats unavailable"}}
    ).call

    assert_empty findings
  end
end
