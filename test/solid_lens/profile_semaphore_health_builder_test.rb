# frozen_string_literal: true

require "test_helper"
require "solid_lens/collectors/profile_evidence/semaphore_health_builder"

class ProfileSemaphoreHealthBuilderTest < Minitest::Test
  def test_build_summarizes_semaphore_health_profile
    samples = [
      sample(offset_seconds: 0.0, semaphore_count: 0),
      sample(
        offset_seconds: 5.0,
        semaphore_count: 2,
        expired_semaphore_count: 1,
        oldest_expired_semaphore_lag_seconds: 45.0,
        expired_orphan_semaphore_count: 1,
        oldest_expired_orphan_semaphore_lag_seconds: 45.0,
        expired_orphan_semaphore_keys: ["account:42"]
      ),
      sample(offset_seconds: 10.0, semaphore_count: 0)
    ]

    result = build(samples)

    assert_equal 2, result.fetch(:peak_count)
    assert_equal 1, result.fetch(:peak_expired_count)
    assert_equal 1, result.fetch(:peak_expired_orphan_count)
    assert_equal ["account:42"], result.fetch(:peak_expired_orphan_keys)
    assert_equal 3, result.fetch(:timeline).size
  end

  private

  def build(samples)
    sample_set = SolidLens::Collectors::ProfileEvidence::SampleSet.new(samples: samples, duration: 10.0)

    SolidLens::Collectors::ProfileEvidence::SemaphoreHealthBuilder.new(sample_set: sample_set).build
  end

  def sample(
    offset_seconds:,
    semaphore_count:,
    expired_semaphore_count: 0,
    oldest_expired_semaphore_lag_seconds: 0.0,
    expired_orphan_semaphore_count: 0,
    oldest_expired_orphan_semaphore_lag_seconds: 0.0,
    expired_orphan_semaphore_keys: []
  )
    {
      offset_seconds: offset_seconds,
      evidence: {
        tables: {
          counts: {"solid_queue_semaphores" => semaphore_count},
          expired_semaphore_count: expired_semaphore_count,
          oldest_expired_semaphore_lag_seconds: oldest_expired_semaphore_lag_seconds,
          expired_orphan_semaphore_count: expired_orphan_semaphore_count,
          oldest_expired_orphan_semaphore_lag_seconds: oldest_expired_orphan_semaphore_lag_seconds,
          expired_orphan_semaphore_keys: expired_orphan_semaphore_keys
        }
      }
    }
  end
end
