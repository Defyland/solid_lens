# frozen_string_literal: true

require "test_helper"

class ProfileMaintenanceHealthBuilderTest < Minitest::Test
  def test_build_assembles_all_maintenance_profiles
    samples = [
      sample(offset_seconds: 0.0, semaphore_count: 0, claimed_dead_count: 0, bloat: {}),
      sample(
        offset_seconds: 5.0,
        semaphore_count: 2,
        expired_semaphore_count: 1,
        oldest_expired_semaphore_lag_seconds: 45.0,
        expired_orphan_semaphore_count: 1,
        oldest_expired_orphan_semaphore_lag_seconds: 45.0,
        expired_orphan_semaphore_keys: ["account:42"],
        claimed_dead_count: 1,
        oldest_claimed_dead_lag_seconds: 60.0,
        process_alive_threshold_seconds: 30,
        bloat: {"solid_queue_ready_executions" => {live_tuples: 100, dead_tuples: 1_500, dead_tuple_ratio: 0.3}}
      ),
      sample(offset_seconds: 10.0, semaphore_count: 0, claimed_dead_count: 0, process_alive_threshold_seconds: 30, bloat: {})
    ]

    result = build(samples)

    assert_equal %i[bloat_health claimed_execution_health semaphore_health], result.keys.sort
  end

  private

  def build(samples)
    sample_set = SolidLens::Collectors::ProfileEvidence::SampleSet.new(samples: samples, duration: 10.0)

    SolidLens::Collectors::ProfileEvidence::MaintenanceHealthBuilder.new(sample_set: sample_set).build
  end

  def sample(
    offset_seconds:,
    semaphore_count:,
    claimed_dead_count:,
    bloat:,
    expired_semaphore_count: 0,
    oldest_expired_semaphore_lag_seconds: 0.0,
    expired_orphan_semaphore_count: 0,
    oldest_expired_orphan_semaphore_lag_seconds: 0.0,
    expired_orphan_semaphore_keys: [],
    oldest_claimed_dead_lag_seconds: 0.0,
    process_alive_threshold_seconds: nil
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
          expired_orphan_semaphore_keys: expired_orphan_semaphore_keys,
          claimed_by_dead_process_count: claimed_dead_count,
          oldest_claimed_dead_lag_seconds: oldest_claimed_dead_lag_seconds,
          process_alive_threshold_seconds: process_alive_threshold_seconds,
          bloat: bloat
        }
      }
    }
  end
end
