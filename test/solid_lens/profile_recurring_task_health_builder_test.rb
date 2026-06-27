# frozen_string_literal: true

require "test_helper"
require "solid_lens/collectors/profile_evidence/recurring_task_health_builder"

class ProfileRecurringTaskHealthBuilderTest < Minitest::Test
  def test_build_summarizes_recurring_task_health_profile
    result = build([
      sample(offset_seconds: 0.0, overdue_recurring_task_count: 0, oldest_recurring_task_lag_seconds: 0.0),
      sample(
        offset_seconds: 5.0,
        overdue_recurring_task_count: 1,
        oldest_recurring_task_lag_seconds: 20.0,
        overdue_recurring_task_keys: ["nightly_cleanup"]
      ),
      sample(
        offset_seconds: 10.0,
        overdue_recurring_task_count: 1,
        oldest_recurring_task_lag_seconds: 10.0,
        overdue_recurring_task_keys: ["nightly_cleanup"]
      )
    ])

    assert_equal 1, result.fetch(:finish_overdue_count)
    assert_equal ["nightly_cleanup"], result.fetch(:finish_overdue_task_keys)
    assert_equal 20.0, result.fetch(:peak_oldest_lag_seconds)
    assert_equal ["nightly_cleanup"], result.fetch(:peak_overdue_task_keys)
  end

  private

  def build(samples)
    sample_set = SolidLens::Collectors::ProfileEvidence::SampleSet.new(samples: samples, duration: 10.0)

    SolidLens::Collectors::ProfileEvidence::RecurringTaskHealthBuilder.new(sample_set: sample_set).build
  end

  def sample(offset_seconds:, overdue_recurring_task_count:, oldest_recurring_task_lag_seconds:, overdue_recurring_task_keys: [])
    {
      offset_seconds: offset_seconds,
      evidence: {
        tables: {
          overdue_recurring_task_count: overdue_recurring_task_count,
          oldest_recurring_task_lag_seconds: oldest_recurring_task_lag_seconds,
          overdue_recurring_task_keys: overdue_recurring_task_keys
        }
      }
    }
  end
end
