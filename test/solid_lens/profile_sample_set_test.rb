# frozen_string_literal: true

require "test_helper"
require "solid_lens/collectors/profile_evidence/sample_set"

class ProfileSampleSetTest < Minitest::Test
  def test_table_and_metric_helpers_summarize_profile_samples
    sample_set = build_sample_set(
      [
        sample(
          offset_seconds: 0.0,
          counts: {"solid_queue_ready_executions" => 1},
          metrics: {oldest_ready_age_seconds: 2.0}
        ),
        sample(
          offset_seconds: 5.0,
          counts: {"solid_queue_ready_executions" => 3, "solid_queue_blocked_executions" => 1},
          metrics: {oldest_ready_age_seconds: 5.5}
        )
      ],
      duration: 10.0
    )

    assert_equal({"solid_queue_ready_executions" => 2, "solid_queue_blocked_executions" => 1}, sample_set.table_count_delta)
    assert_equal({"solid_queue_ready_executions" => 0.2, "solid_queue_blocked_executions" => 0.1}, sample_set.table_count_rate_per_second)
    assert_equal 1, sample_set.start_count("solid_queue_ready_executions")
    assert_equal 3, sample_set.finish_count("solid_queue_ready_executions")
    assert_equal 2.0, sample_set.start_metric(:oldest_ready_age_seconds).to_f
    assert_equal 5.5, sample_set.finish_metric(:oldest_ready_age_seconds).to_f
    assert_equal 7, sample_set.finish_metric(:missing_metric, default: 7)
  end

  def test_hash_peak_and_queue_delta_helpers_stay_deterministic
    sample_set = build_sample_set(
      [
        sample(
          offset_seconds: 0.0,
          metrics: {
            ready_queue_depth_by_queue: {"default" => 1, "mailers" => 0}
          }
        ),
        sample(
          offset_seconds: 5.0,
          metrics: {
            ready_queue_depth_by_queue: {"default" => 3, "critical" => 2}
          }
        ),
        sample(
          offset_seconds: 10.0,
          metrics: {
            ready_queue_depth_by_queue: {"default" => 2, "critical" => 2}
          }
        )
      ],
      duration: 10.0
    )

    assert_equal({"default" => 1, "mailers" => 0}, sample_set.start_hash_metric(:ready_queue_depth_by_queue))
    assert_equal({"default" => 2, "critical" => 2}, sample_set.finish_hash_metric(:ready_queue_depth_by_queue))
    assert_equal({"critical" => 2, "default" => 3, "mailers" => 0}, sample_set.peak_hash_metric(:ready_queue_depth_by_queue))
    assert_equal({"critical" => 2, "default" => 1}, sample_set.queue_deltas(
      sample_set.start_hash_metric(:ready_queue_depth_by_queue),
      sample_set.finish_hash_metric(:ready_queue_depth_by_queue)
    ))

    peak_sample = sample_set.peak_sample_for { |sample| sample_set.hash_metric(sample, :ready_queue_depth_by_queue).fetch("default", 0) }

    assert_equal 5.0, sample_set.offset(peak_sample)
  end

  private

  def build_sample_set(samples, duration:)
    SolidLens::Collectors::ProfileEvidence::SampleSet.new(samples: samples, duration: duration)
  end

  def sample(offset_seconds:, counts: {}, metrics: {})
    {
      offset_seconds: offset_seconds,
      evidence: {
        tables: {
          counts: counts
        }.merge(metrics)
      }
    }
  end
end
