# frozen_string_literal: true

require "test_helper"
require "solid_lens/collectors/profile_evidence/scheduled_backlog_builder"

class ProfileScheduledBacklogBuilderTest < Minitest::Test
  def test_build_summarizes_scheduled_backlog_profile
    result = build([
      sample(offset_seconds: 0.0, overdue_scheduled_count: 0, oldest_scheduled_lag_seconds: 0.0),
      sample(offset_seconds: 5.0, overdue_scheduled_count: 2, oldest_scheduled_lag_seconds: 40.0),
      sample(offset_seconds: 10.0, overdue_scheduled_count: 0, oldest_scheduled_lag_seconds: 0.0)
    ])

    assert_equal 2, result.fetch(:peak_overdue_count)
    assert_equal 5.0, result.fetch(:peak_overdue_at_seconds)
    assert_equal 40.0, result.fetch(:peak_oldest_lag_seconds)
    assert_equal 0, result.fetch(:finish_overdue_count)
  end

  private

  def build(samples)
    sample_set = SolidLens::Collectors::ProfileEvidence::SampleSet.new(samples: samples, duration: 10.0)

    SolidLens::Collectors::ProfileEvidence::ScheduledBacklogBuilder.new(sample_set: sample_set).build
  end

  def sample(offset_seconds:, overdue_scheduled_count:, oldest_scheduled_lag_seconds:)
    {
      offset_seconds: offset_seconds,
      evidence: {
        tables: {
          overdue_scheduled_count: overdue_scheduled_count,
          oldest_scheduled_lag_seconds: oldest_scheduled_lag_seconds
        }
      }
    }
  end
end
