# frozen_string_literal: true

require "test_helper"

class ProfileCollectorTest < Minitest::Test
  def test_profile_collector_tracks_peaks_across_samples
    clock = 0.0
    samples = [
      sample_evidence(
        ready_count: 0,
        overdue_count: 0,
        blocked_count: 0,
        semaphore_count: 0,
        claimed_dead_count: 0,
        expired_orphan_semaphore_count: 0,
        oldest_expired_orphan_semaphore_lag_seconds: 0.0,
        overdue_recurring_task_count: 0,
        oldest_recurring_task_lag_seconds: 0.0,
        bloat: {"solid_queue_ready_executions" => {live_tuples: 100, dead_tuples: 0, dead_tuple_ratio: 0.0}}
      ),
      sample_evidence(
        ready_count: 3,
        ready_by_queue: {"critical" => 3},
        oldest_ready_age_seconds: 12.0,
        overdue_count: 2,
        oldest_scheduled_lag_seconds: 90.0,
        blocked_count: 2,
        blocked_by_queue: {"critical" => 2},
        oldest_blocked_age_seconds: 15.0,
        expired_blocked_count: 1,
        oldest_expired_blocked_lag_seconds: 40.0,
        semaphore_count: 2,
        expired_semaphore_count: 1,
        oldest_expired_semaphore_lag_seconds: 45.0,
        expired_orphan_semaphore_count: 1,
        oldest_expired_orphan_semaphore_lag_seconds: 45.0,
        expired_orphan_semaphore_keys: ["profile-semaphore"],
        claimed_dead_count: 1,
        oldest_claimed_dead_lag_seconds: 50.0,
        overdue_recurring_task_count: 1,
        oldest_recurring_task_lag_seconds: 30.0,
        overdue_recurring_task_keys: ["nightly_cleanup"],
        bloat: {"solid_queue_ready_executions" => {live_tuples: 100, dead_tuples: 1_500, dead_tuple_ratio: 0.3}}
      ),
      sample_evidence(
        ready_count: 0,
        overdue_count: 0,
        blocked_count: 0,
        semaphore_count: 0,
        claimed_dead_count: 0,
        expired_orphan_semaphore_count: 0,
        oldest_expired_orphan_semaphore_lag_seconds: 0.0,
        overdue_recurring_task_count: 0,
        oldest_recurring_task_lag_seconds: 0.0,
        bloat: {"solid_queue_ready_executions" => {live_tuples: 100, dead_tuples: 0, dead_tuple_ratio: 0.0}}
      )
    ]

    result = SolidLens::Collectors::ProfileCollector.new(
      evidence_collector: -> { samples.shift },
      duration: 0.2,
      sample_interval: 0.1,
      sleeper: ->(seconds) { clock += seconds },
      monotonic_clock: -> { clock }
    ).collect

    profile = result.fetch(:profile)

    assert_equal 3, profile.fetch(:sample_count)
    assert_equal 0.1, profile.fetch(:requested_sample_interval_seconds)
    assert_equal 0.1, profile.fetch(:sample_interval_seconds)
    assert_equal false, profile.fetch(:sample_limit_applied)
    assert_equal 3, profile.fetch(:ready_backlog).fetch(:peak_count)
    assert_equal 0, profile.fetch(:ready_backlog).fetch(:finish_count)
    assert_equal({"critical" => 3}, profile.fetch(:ready_backlog).fetch(:peak_by_queue))
    assert_equal 2, profile.fetch(:scheduled_backlog).fetch(:peak_overdue_count)
    assert_equal 0, profile.fetch(:scheduled_backlog).fetch(:finish_overdue_count)
    assert_equal 1, profile.fetch(:recurring_task_health).fetch(:peak_overdue_count)
    assert_equal 0, profile.fetch(:recurring_task_health).fetch(:finish_overdue_count)
    assert_equal ["nightly_cleanup"], profile.fetch(:recurring_task_health).fetch(:peak_overdue_task_keys)
    assert_equal 2, profile.fetch(:blocked_backlog).fetch(:peak_count)
    assert_equal 1, profile.fetch(:blocked_backlog).fetch(:peak_expired_count)
    assert_equal({"critical" => 2}, profile.fetch(:blocked_backlog).fetch(:peak_by_queue))
    assert_equal 1, profile.fetch(:semaphore_health).fetch(:peak_expired_count)
    assert_equal 0, profile.fetch(:semaphore_health).fetch(:finish_expired_count)
    assert_equal 1, profile.fetch(:semaphore_health).fetch(:peak_expired_orphan_count)
    assert_equal ["profile-semaphore"], profile.fetch(:semaphore_health).fetch(:peak_expired_orphan_keys)
    assert_equal 1, profile.fetch(:claimed_execution_health).fetch(:peak_dead_count)
    assert_equal 0, profile.fetch(:claimed_execution_health).fetch(:finish_dead_count)
    bloat = profile.fetch(:bloat_health).fetch(:tables).fetch("solid_queue_ready_executions")
    assert_equal 1_500, bloat.fetch(:peak_dead_tuples)
    assert_equal 0, bloat.fetch(:finish_dead_tuples)
    assert_equal 0.3, bloat.fetch(:peak_dead_tuple_ratio)
  end

  def test_profile_collector_adapts_sampling_interval_to_cap_timeline_size
    clock = 0.0
    result = SolidLens::Collectors::ProfileCollector.new(
      evidence_collector: -> { sample_evidence(ready_count: 0, overdue_count: 0, blocked_count: 0, semaphore_count: 0, claimed_dead_count: 0) },
      duration: 1.0,
      sample_interval: 0.1,
      max_samples: 5,
      sleeper: ->(seconds) { clock += seconds },
      monotonic_clock: -> { clock }
    ).collect

    profile = result.fetch(:profile)
    offsets = profile.fetch(:ready_backlog).fetch(:timeline).map { |sample| sample.fetch(:offset_seconds) }

    assert_equal 0.1, profile.fetch(:requested_sample_interval_seconds)
    assert_equal 0.25, profile.fetch(:sample_interval_seconds)
    assert_equal true, profile.fetch(:sample_limit_applied)
    assert_equal 5, profile.fetch(:max_samples)
    assert_equal 5, profile.fetch(:sample_count)
    assert_equal [0.0, 0.25, 0.5, 0.75, 1.0], offsets
  end

  def test_profile_collector_keeps_target_sample_schedule_despite_collection_overhead
    clock = 0.0
    result = SolidLens::Collectors::ProfileCollector.new(
      evidence_collector: lambda {
        current = sample_evidence(ready_count: 0, overdue_count: 0, blocked_count: 0, semaphore_count: 0, claimed_dead_count: 0)
        clock += 0.05
        current
      },
      duration: 1.0,
      sample_interval: 0.2,
      sleeper: ->(seconds) { clock += seconds },
      monotonic_clock: -> { clock }
    ).collect

    profile = result.fetch(:profile)
    offsets = profile.fetch(:ready_backlog).fetch(:timeline).map { |sample| sample.fetch(:offset_seconds) }

    assert_equal [0.0, 0.2, 0.4, 0.6, 0.8, 1.0], offsets
    assert_equal 6, profile.fetch(:sample_count)
  end

  private

  def sample_evidence(
    ready_count:,
    overdue_count:,
    blocked_count:,
    semaphore_count:,
    claimed_dead_count:,
    ready_by_queue: {},
    blocked_by_queue: {},
    oldest_ready_age_seconds: 0.0,
    oldest_scheduled_lag_seconds: 0.0,
    oldest_blocked_age_seconds: 0.0,
    expired_blocked_count: 0,
    oldest_expired_blocked_lag_seconds: 0.0,
    expired_semaphore_count: 0,
    oldest_expired_semaphore_lag_seconds: 0.0,
    expired_orphan_semaphore_count: 0,
    oldest_expired_orphan_semaphore_lag_seconds: 0.0,
    expired_orphan_semaphore_keys: [],
    oldest_claimed_dead_lag_seconds: 0.0,
    overdue_recurring_task_count: 0,
    oldest_recurring_task_lag_seconds: 0.0,
    overdue_recurring_task_keys: [],
    bloat: {}
  )
    {
      tables: {
        counts: {
          "solid_queue_ready_executions" => ready_count,
          "solid_queue_scheduled_executions" => overdue_count,
          "solid_queue_blocked_executions" => blocked_count,
          "solid_queue_semaphores" => semaphore_count
        },
        ready_queue_depth_by_queue: ready_by_queue,
        blocked_queue_depth_by_queue: blocked_by_queue,
        oldest_ready_age_seconds: oldest_ready_age_seconds,
        overdue_scheduled_count: overdue_count,
        oldest_scheduled_lag_seconds: oldest_scheduled_lag_seconds,
        oldest_blocked_age_seconds: oldest_blocked_age_seconds,
        expired_blocked_execution_count: expired_blocked_count,
        oldest_expired_blocked_lag_seconds: oldest_expired_blocked_lag_seconds,
        expired_semaphore_count: expired_semaphore_count,
        oldest_expired_semaphore_lag_seconds: oldest_expired_semaphore_lag_seconds,
        expired_orphan_semaphore_count: expired_orphan_semaphore_count,
        oldest_expired_orphan_semaphore_lag_seconds: oldest_expired_orphan_semaphore_lag_seconds,
        expired_orphan_semaphore_keys: expired_orphan_semaphore_keys,
        claimed_by_dead_process_count: claimed_dead_count,
        oldest_claimed_dead_lag_seconds: oldest_claimed_dead_lag_seconds,
        overdue_recurring_task_count: overdue_recurring_task_count,
        oldest_recurring_task_lag_seconds: oldest_recurring_task_lag_seconds,
        overdue_recurring_task_keys: overdue_recurring_task_keys,
        bloat: bloat
      }
    }
  end
end
