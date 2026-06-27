# frozen_string_literal: true

require "test_helper"

class ProfileMaintenanceChecksTest < Minitest::Test
  def test_profile_semaphore_health_check_flags_growth
    findings = SolidLens::Checks::ProfileSemaphoreHealthCheck.new(
      profile: {
        semaphore_health: {
          start_count: 0,
          finish_count: 1,
          peak_count: 1,
          count_delta: 1,
          start_expired_count: 0,
          finish_expired_count: 1,
          peak_expired_count: 1,
          expired_count_delta: 1,
          start_oldest_expired_lag_seconds: 0.0,
          finish_oldest_expired_lag_seconds: 20.0,
          peak_oldest_expired_lag_seconds: 20.0,
          oldest_expired_lag_delta_seconds: 20.0
        }
      }
    ).call

    finding = findings.fetch(0)

    assert_equal "solid_queue.profile.semaphores.expired_growing", finding.id
    assert_equal :medium, finding.severity
    assert_equal 1, finding.evidence.fetch(:finish_expired_count)
  end

  def test_profile_semaphore_health_check_flags_orphan_growth
    findings = SolidLens::Checks::ProfileSemaphoreHealthCheck.new(
      profile: {
        semaphore_health: {
          start_count: 0,
          finish_count: 1,
          peak_count: 1,
          count_delta: 1,
          start_expired_count: 0,
          finish_expired_count: 1,
          peak_expired_count: 1,
          expired_count_delta: 1,
          start_oldest_expired_lag_seconds: 0.0,
          finish_oldest_expired_lag_seconds: 20.0,
          peak_oldest_expired_lag_seconds: 20.0,
          oldest_expired_lag_delta_seconds: 20.0,
          start_expired_orphan_count: 0,
          finish_expired_orphan_count: 1,
          peak_expired_orphan_count: 1,
          expired_orphan_count_delta: 1,
          start_oldest_expired_orphan_lag_seconds: 0.0,
          finish_oldest_expired_orphan_lag_seconds: 20.0,
          peak_oldest_expired_orphan_lag_seconds: 20.0,
          oldest_expired_orphan_lag_delta_seconds: 20.0,
          finish_expired_orphan_keys: ["account:88"],
          peak_expired_orphan_keys: ["account:88"]
        }
      }
    ).call

    finding = findings.find { |item| item.id == "solid_queue.profile.semaphores.orphaned_growing" }

    refute_nil finding
    assert_equal :medium, finding.severity
    assert_equal ["account:88"], finding.evidence.fetch(:finish_expired_orphan_keys)
  end

  def test_profile_claimed_executions_check_flags_growth
    findings = SolidLens::Checks::ProfileClaimedExecutionsCheck.new(
      profile: {
        claimed_execution_health: {
          process_alive_threshold_seconds: 30,
          start_dead_count: 0,
          finish_dead_count: 1,
          peak_dead_count: 1,
          dead_count_delta: 1,
          start_oldest_dead_lag_seconds: 0.0,
          finish_oldest_dead_lag_seconds: 20.0,
          peak_oldest_dead_lag_seconds: 20.0,
          oldest_dead_lag_delta_seconds: 20.0
        }
      }
    ).call

    finding = findings.fetch(0)

    assert_equal "solid_queue.profile.claimed.dead_process.growing", finding.id
    assert_equal :high, finding.severity
    assert_equal 1, finding.evidence.fetch(:finish_dead_count)
  end

  def test_profile_table_bloat_check_flags_recovered_spike
    findings = SolidLens::Checks::ProfileTableBloatCheck.new(
      profile: {
        bloat_health: {
          tables: {
            "solid_queue_ready_executions" => {
              start_live_tuples: 100,
              finish_live_tuples: 100,
              live_tuple_delta: 0,
              start_dead_tuples: 0,
              finish_dead_tuples: 0,
              peak_dead_tuples: 1_500,
              peak_dead_tuples_at_seconds: 5.0,
              dead_tuple_delta: 0,
              dead_tuple_rate_per_second: 0.0,
              start_dead_tuple_ratio: 0.0,
              finish_dead_tuple_ratio: 0.0,
              peak_dead_tuple_ratio: 0.3,
              peak_dead_tuple_ratio_at_seconds: 5.0,
              dead_tuple_ratio_delta: 0.0
            }
          }
        }
      }
    ).call

    finding = findings.fetch(0)

    assert_equal "solid_queue.profile.tables.bloat.growing", finding.id
    assert_equal :medium, finding.severity
    assert_equal 1_500, finding.evidence.fetch(:tables).fetch("solid_queue_ready_executions").fetch(:peak_dead_tuples)
  end

  def test_profile_table_bloat_check_ignores_small_dead_tuple_noise
    findings = SolidLens::Checks::ProfileTableBloatCheck.new(
      profile: {
        bloat_health: {
          tables: {
            "solid_queue_ready_executions" => {
              start_live_tuples: 100,
              finish_live_tuples: 100,
              live_tuple_delta: 0,
              start_dead_tuples: 0,
              finish_dead_tuples: 100,
              peak_dead_tuples: 100,
              peak_dead_tuples_at_seconds: 5.0,
              dead_tuple_delta: 100,
              dead_tuple_rate_per_second: 1.0,
              start_dead_tuple_ratio: 0.0,
              finish_dead_tuple_ratio: 0.05,
              peak_dead_tuple_ratio: 0.05,
              peak_dead_tuple_ratio_at_seconds: 5.0,
              dead_tuple_ratio_delta: 0.05
            }
          }
        }
      }
    ).call

    assert_empty findings
  end
end
