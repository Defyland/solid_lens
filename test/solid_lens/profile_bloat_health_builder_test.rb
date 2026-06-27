# frozen_string_literal: true

require "test_helper"
require "solid_lens/collectors/profile_evidence/bloat_health_builder"

class ProfileBloatHealthBuilderTest < Minitest::Test
  def test_build_summarizes_active_bloat_tables
    samples = [
      sample(offset_seconds: 0.0, bloat: {"solid_queue_ready_executions" => {live_tuples: 100, dead_tuples: 0, dead_tuple_ratio: 0.0}}),
      sample(offset_seconds: 5.0, bloat: {"solid_queue_ready_executions" => {live_tuples: 100, dead_tuples: 1_500, dead_tuple_ratio: 0.3}}),
      sample(offset_seconds: 10.0, bloat: {"solid_queue_ready_executions" => {live_tuples: 100, dead_tuples: 0, dead_tuple_ratio: 0.0}})
    ]

    result = build(samples)

    table = result.fetch(:tables).fetch("solid_queue_ready_executions")

    assert_equal 1_500, table.fetch(:peak_dead_tuples)
    assert_equal 0.3, table.fetch(:peak_dead_tuple_ratio)
  end

  def test_build_preserves_bloat_error
    samples = [
      sample(offset_seconds: 0.0, bloat: {"error" => "pg_stat_user_tables unavailable"}),
      sample(offset_seconds: 5.0, bloat: {"solid_queue_ready_executions" => {live_tuples: 100, dead_tuples: 100, dead_tuple_ratio: 0.1}})
    ]

    result = build(samples)

    assert_equal "pg_stat_user_tables unavailable", result.fetch(:error)
    assert_equal({}, result.fetch(:tables))
  end

  private

  def build(samples)
    sample_set = SolidLens::Collectors::ProfileEvidence::SampleSet.new(samples: samples, duration: 10.0)

    SolidLens::Collectors::ProfileEvidence::BloatHealthBuilder.new(sample_set: sample_set).build
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
