# frozen_string_literal: true

require "test_helper"

class ProfileBacklogChecksTest < Minitest::Test
  def test_profile_ready_backlog_check_flags_growth
    findings = SolidLens::Checks::ProfileReadyBacklogCheck.new(
      profile: {
        ready_backlog: {
          start_count: 2,
          finish_count: 5,
          peak_count: 5,
          delta: 3,
          rate_per_second: 1.5,
          start_oldest_age_seconds: 10.0,
          finish_oldest_age_seconds: 12.0,
          peak_oldest_age_seconds: 12.0,
          oldest_age_delta_seconds: 2.0,
          peak_by_queue: {"critical" => 5},
          queue_deltas: {"critical" => 3}
        }
      }
    ).call

    finding = findings.fetch(0)

    assert_equal "solid_queue.profile.ready_backlog.growing", finding.id
    assert_equal :medium, finding.severity
    assert_equal 3, finding.evidence.fetch(:queue_deltas).fetch("critical")
  end

  def test_profile_ready_backlog_check_flags_spike_even_when_finish_recovers
    findings = SolidLens::Checks::ProfileReadyBacklogCheck.new(
      profile: {
        ready_backlog: {
          start_count: 0,
          finish_count: 0,
          peak_count: 4,
          start_oldest_age_seconds: 0.0,
          finish_oldest_age_seconds: 0.0,
          peak_oldest_age_seconds: 10.0,
          delta: 0,
          oldest_age_delta_seconds: 0.0,
          peak_by_queue: {"critical" => 4},
          queue_deltas: {}
        }
      }
    ).call

    finding = findings.fetch(0)

    assert_equal "solid_queue.profile.ready_backlog.growing", finding.id
    assert_equal :medium, finding.severity
    assert_equal 4, finding.evidence.fetch(:peak_by_queue).fetch("critical")
  end

  def test_profile_scheduled_backlog_check_flags_growth
    findings = SolidLens::Checks::ProfileScheduledBacklogCheck.new(
      profile: {
        scheduled_backlog: {
          start_overdue_count: 0,
          finish_overdue_count: 2,
          peak_overdue_count: 2,
          overdue_count_delta: 2,
          overdue_rate_per_second: 1.0,
          start_oldest_lag_seconds: 0.0,
          finish_oldest_lag_seconds: 5.0,
          peak_oldest_lag_seconds: 5.0,
          oldest_lag_delta_seconds: 5.0
        }
      }
    ).call

    finding = findings.fetch(0)

    assert_equal "solid_queue.profile.scheduled_backlog.growing", finding.id
    assert_equal :medium, finding.severity
    assert_equal 2, finding.evidence.fetch(:finish_overdue_count)
  end

  def test_profile_recurring_tasks_check_flags_growth
    findings = SolidLens::Checks::ProfileRecurringTasksCheck.new(
      queue_config: {scheduler_count: 1, scheduler: {"polling_interval" => 1}},
      profile: {
        recurring_task_health: {
          start_overdue_count: 0,
          finish_overdue_count: 1,
          peak_overdue_count: 1,
          overdue_count_delta: 1,
          overdue_rate_per_second: 0.5,
          start_oldest_lag_seconds: 0.0,
          finish_oldest_lag_seconds: 30.0,
          peak_oldest_lag_seconds: 30.0,
          oldest_lag_delta_seconds: 30.0,
          finish_overdue_task_keys: ["nightly_cleanup"],
          peak_overdue_task_keys: ["nightly_cleanup"]
        }
      }
    ).call

    finding = findings.fetch(0)

    assert_equal "solid_queue.profile.recurring.overdue_growing", finding.id
    assert_equal :medium, finding.severity
    assert_equal ["nightly_cleanup"], finding.evidence.fetch(:finish_overdue_task_keys)
  end

  def test_profile_recurring_tasks_check_escalates_when_scheduler_is_missing
    findings = SolidLens::Checks::ProfileRecurringTasksCheck.new(
      queue_config: {scheduler_count: 0, scheduler: {"dynamic_tasks_enabled" => true}},
      profile: {
        recurring_task_health: {
          start_overdue_count: 0,
          finish_overdue_count: 1,
          peak_overdue_count: 1,
          overdue_count_delta: 1,
          overdue_rate_per_second: 0.5,
          start_oldest_lag_seconds: 0.0,
          finish_oldest_lag_seconds: 30.0,
          peak_oldest_lag_seconds: 30.0,
          oldest_lag_delta_seconds: 30.0
        }
      }
    ).call

    finding = findings.fetch(0)

    assert_equal :high, finding.severity
    assert_equal 0, finding.evidence.fetch(:scheduler_count)
  end

  def test_profile_recurring_tasks_check_escalates_when_scheduler_is_unusable
    findings = SolidLens::Checks::ProfileRecurringTasksCheck.new(
      queue_config: {scheduler_count: 1, scheduler: {"polling_interval" => 0, "dynamic_tasks_enabled" => true}},
      profile: {
        recurring_task_health: {
          start_overdue_count: 0,
          finish_overdue_count: 1,
          peak_overdue_count: 1,
          overdue_count_delta: 1,
          overdue_rate_per_second: 0.5,
          start_oldest_lag_seconds: 0.0,
          finish_oldest_lag_seconds: 30.0,
          peak_oldest_lag_seconds: 30.0,
          oldest_lag_delta_seconds: 30.0
        }
      }
    ).call

    finding = findings.fetch(0)

    assert_equal :high, finding.severity
    assert_equal 1, finding.evidence.fetch(:scheduler_count)
    assert_includes finding.evidence.fetch(:scheduler_issues), "polling_interval_must_be_positive"
  end

  def test_profile_blocked_backlog_check_flags_growth
    findings = SolidLens::Checks::ProfileBlockedBacklogCheck.new(
      profile: {
        blocked_backlog: {
          start_count: 0,
          finish_count: 1,
          peak_count: 1,
          count_delta: 1,
          start_oldest_age_seconds: 0.0,
          finish_oldest_age_seconds: 5.0,
          peak_oldest_age_seconds: 5.0,
          oldest_age_delta_seconds: 5.0,
          start_expired_count: 0,
          finish_expired_count: 1,
          peak_expired_count: 1,
          expired_count_delta: 1,
          start_oldest_expired_lag_seconds: 0.0,
          finish_oldest_expired_lag_seconds: 10.0,
          peak_oldest_expired_lag_seconds: 10.0,
          oldest_expired_lag_delta_seconds: 10.0,
          peak_by_queue: {"critical" => 1},
          queue_deltas: {"critical" => 1}
        }
      }
    ).call

    finding = findings.fetch(0)

    assert_equal "solid_queue.profile.blocked_backlog.growing", finding.id
    assert_equal :medium, finding.severity
    assert_equal 1, finding.evidence.fetch(:finish_expired_count)
  end
end
