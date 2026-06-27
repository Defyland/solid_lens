# frozen_string_literal: true

require "test_helper"
require "solid_lens/collectors/profile_evidence/bloat_sample_set"

class ProfileBloatSampleSetTest < Minitest::Test
  def test_error_returns_first_reported_bloat_error
    bloat_sample_set = build_sample_set(
      [
        sample(offset_seconds: 0.0, bloat: {error: "pg_stat_user_tables unavailable"}),
        sample(offset_seconds: 5.0, bloat: {"error" => "ignored later error"})
      ]
    )

    assert_equal "pg_stat_user_tables unavailable", bloat_sample_set.error
  end

  def test_table_names_and_stats_only_include_active_tables
    samples = [
      sample(
        offset_seconds: 0.0,
        bloat: {
          "solid_queue_ready_executions" => {live_tuples: 100, dead_tuples: 0, dead_tuple_ratio: 0.0},
          "solid_queue_scheduled_executions" => {live_tuples: 80, dead_tuples: 1, dead_tuple_ratio: 0.0123}
        }
      ),
      sample(
        offset_seconds: 5.0,
        bloat: {
          "solid_queue_ready_executions" => {live_tuples: 100, dead_tuples: 12, dead_tuple_ratio: 0.1071},
          "solid_queue_claimed_executions" => {live_tuples: 40, dead_tuples: 0, dead_tuple_ratio: 0.2}
        }
      )
    ]
    bloat_sample_set = build_sample_set(samples)

    assert_equal %w[solid_queue_claimed_executions solid_queue_ready_executions solid_queue_scheduled_executions], bloat_sample_set.table_names
    assert_equal 100, bloat_sample_set.live_tuples(samples.last, "solid_queue_ready_executions")
    assert_equal 12, bloat_sample_set.dead_tuples(samples.last, "solid_queue_ready_executions")
    assert_equal 0.1071, bloat_sample_set.dead_tuple_ratio(samples.last, "solid_queue_ready_executions")
  end

  private

  def build_sample_set(samples)
    SolidLens::Collectors::ProfileEvidence::BloatSampleSet.new(samples: samples)
  end

  def sample(offset_seconds:, bloat:)
    {
      offset_seconds: offset_seconds,
      evidence: {
        tables: {
          bloat: bloat
        }
      }
    }
  end
end
