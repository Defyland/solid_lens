# frozen_string_literal: true

require "test_helper"
require "solid_lens/collectors/profile_evidence/blocked_backlog_builder"

class ProfileBlockedBacklogBuilderTest < Minitest::Test
  def test_build_summarizes_blocked_backlog_profile
    result = build([
      sample(offset_seconds: 0.0, blocked_count: 0),
      sample(
        offset_seconds: 5.0,
        blocked_count: 2,
        blocked_by_queue: {"critical" => 2},
        oldest_blocked_age_seconds: 15.0,
        expired_blocked_count: 1,
        oldest_expired_blocked_lag_seconds: 30.0
      ),
      sample(
        offset_seconds: 10.0,
        blocked_count: 1,
        blocked_by_queue: {"critical" => 1},
        oldest_blocked_age_seconds: 8.0,
        expired_blocked_count: 1,
        oldest_expired_blocked_lag_seconds: 12.0
      )
    ])

    assert_equal 2, result.fetch(:peak_count)
    assert_equal({"critical" => 2}, result.fetch(:peak_by_queue))
    assert_equal 1, result.fetch(:finish_count)
    assert_equal 1, result.fetch(:expired_count_delta)
    assert_equal 30.0, result.fetch(:peak_oldest_expired_lag_seconds)
  end

  private

  def build(samples)
    sample_set = SolidLens::Collectors::ProfileEvidence::SampleSet.new(samples: samples, duration: 10.0)

    SolidLens::Collectors::ProfileEvidence::BlockedBacklogBuilder.new(sample_set: sample_set).build
  end

  def sample(
    offset_seconds:,
    blocked_count:,
    blocked_by_queue: {},
    oldest_blocked_age_seconds: 0.0,
    expired_blocked_count: 0,
    oldest_expired_blocked_lag_seconds: 0.0
  )
    {
      offset_seconds: offset_seconds,
      evidence: {
        tables: {
          counts: {"solid_queue_blocked_executions" => blocked_count},
          blocked_queue_depth_by_queue: blocked_by_queue,
          oldest_blocked_age_seconds: oldest_blocked_age_seconds,
          expired_blocked_execution_count: expired_blocked_count,
          oldest_expired_blocked_lag_seconds: oldest_expired_blocked_lag_seconds
        }
      }
    }
  end
end
