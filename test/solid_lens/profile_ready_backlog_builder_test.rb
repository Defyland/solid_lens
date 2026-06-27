# frozen_string_literal: true

require "test_helper"
require "solid_lens/collectors/profile_evidence/ready_backlog_builder"

class ProfileReadyBacklogBuilderTest < Minitest::Test
  def test_build_summarizes_ready_backlog_profile
    result = build([
      sample(offset_seconds: 0.0, ready_count: 0),
      sample(
        offset_seconds: 5.0,
        ready_count: 3,
        ready_by_queue: {"critical" => 3},
        oldest_ready_age_seconds: 12.0
      ),
      sample(
        offset_seconds: 10.0,
        ready_count: 1,
        ready_by_queue: {"critical" => 1},
        oldest_ready_age_seconds: 5.0
      )
    ])

    assert_equal 3, result.fetch(:peak_count)
    assert_equal({"critical" => 3}, result.fetch(:peak_by_queue))
    assert_equal 1, result.fetch(:finish_count)
    assert_equal({"critical" => 1}, result.fetch(:finish_by_queue))
    assert_equal({"critical" => 1}, result.fetch(:queue_deltas))
  end

  private

  def build(samples)
    sample_set = SolidLens::Collectors::ProfileEvidence::SampleSet.new(samples: samples, duration: 10.0)

    SolidLens::Collectors::ProfileEvidence::ReadyBacklogBuilder.new(sample_set: sample_set).build
  end

  def sample(offset_seconds:, ready_count:, ready_by_queue: {}, oldest_ready_age_seconds: 0.0)
    {
      offset_seconds: offset_seconds,
      evidence: {
        tables: {
          counts: {"solid_queue_ready_executions" => ready_count},
          ready_queue_depth_by_queue: ready_by_queue,
          oldest_ready_age_seconds: oldest_ready_age_seconds
        }
      }
    }
  end
end
