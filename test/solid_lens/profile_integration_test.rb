# frozen_string_literal: true

require "test_helper"

class ProfileIntegrationTest < SolidLensIntegrationCase
  def test_cli_profile_outputs_structured_profile_evidence
    output, error, status = SolidLens::TestSupport::RailsIntegration.capture_cli(
      "profile",
      "--duration=0",
      "--format=json",
      "--rails-env=test"
    )

    assert status.success?, error
    assert_empty error

    report = JSON.parse(output)

    assert_equal "profile", report.fetch("command")
    assert report.fetch("evidence").fetch("profile").key?("ready_backlog")
    assert report.fetch("evidence").fetch("profile").key?("scheduled_backlog")
    assert report.fetch("evidence").fetch("profile").key?("recurring_task_health")
    assert report.fetch("evidence").fetch("profile").key?("bloat_health")
    assert report.fetch("evidence").fetch("profile").key?("requested_sample_interval_seconds")
    assert report.fetch("evidence").fetch("profile").key?("sample_limit_applied")
  end

  def test_cli_profile_honors_sample_interval_option
    output, error, status = SolidLens::TestSupport::RailsIntegration.capture_cli(
      "profile",
      "--duration=1",
      "--sample-interval=0.2",
      "--format=json",
      "--rails-env=test"
    )

    assert status.success?, error
    assert_empty error

    report = JSON.parse(output)

    assert_equal 0.2, report.fetch("evidence").fetch("profile").fetch("sample_interval_seconds")
    assert report.fetch("evidence").fetch("profile").fetch("sample_count") >= 5
  end

  def test_runner_profile_reports_backlog_growth_and_profile_findings
    writer = Thread.new do
      sleep 0.02
      SolidQueue::Record.connection_pool.with_connection do
        create_stale_claimed_execution(last_heartbeat_at: 6.minutes.ago)
        create_ready_execution(queue_name: "critical", created_at: 5.seconds.ago)
        create_ready_execution(queue_name: "critical", created_at: 5.seconds.ago)
        create_scheduled_execution(queue_name: "mailers", scheduled_at: 2.minutes.ago)
        create_dynamic_recurring_task(
          key: "nightly_cleanup",
          schedule: "* * * * *",
          created_at: 3.minutes.ago
        )
        create_blocked_execution(
          queue_name: "critical",
          concurrency_key: "profile-blocked",
          created_at: 5.minutes.ago,
          expires_at: 2.minutes.ago
        )
        create_semaphore(
          key: "profile-semaphore",
          value: 0,
          expires_at: 2.minutes.ago,
          created_at: 5.minutes.ago
        )
      end
    end

    report = SolidLens::Runner.new.profile(duration: 0.3, sample_interval: 0.05)
    writer.join

    profile = report.evidence.fetch(:profile)

    assert profile.fetch(:sample_count) >= 2
    assert_equal 2, profile.fetch(:ready_backlog).fetch(:delta)
    assert_equal 1, profile.fetch(:scheduled_backlog).fetch(:overdue_count_delta)
    assert_equal 1, profile.fetch(:recurring_task_health).fetch(:overdue_count_delta)
    assert_includes profile.fetch(:recurring_task_health).fetch(:finish_overdue_task_keys), "nightly_cleanup"
    assert_equal 2, profile.fetch(:ready_backlog).fetch(:queue_deltas).fetch("critical")
    assert_equal 1, profile.fetch(:blocked_backlog).fetch(:count_delta)
    assert_equal 1, profile.fetch(:blocked_backlog).fetch(:expired_count_delta)
    assert_equal 1, profile.fetch(:semaphore_health).fetch(:expired_count_delta)
    assert_equal 1, profile.fetch(:semaphore_health).fetch(:expired_orphan_count_delta)
    assert_equal 1, profile.fetch(:claimed_execution_health).fetch(:dead_count_delta)
    assert report.findings.any? { |finding| finding.id == "solid_queue.profile.ready_backlog.growing" }
    assert report.findings.any? { |finding| finding.id == "solid_queue.profile.scheduled_backlog.growing" }
    assert report.findings.any? { |finding| finding.id == "solid_queue.profile.recurring.overdue_growing" }
    assert report.findings.any? { |finding| finding.id == "solid_queue.profile.blocked_backlog.growing" }
    assert report.findings.any? { |finding| finding.id == "solid_queue.profile.semaphores.expired_growing" }
    assert report.findings.any? { |finding| finding.id == "solid_queue.profile.semaphores.orphaned_growing" }
    assert report.findings.any? { |finding| finding.id == "solid_queue.profile.claimed.dead_process.growing" }
  ensure
    writer&.join
  end

  def test_runner_profile_captures_ready_spike_that_recovers_before_finish
    writer = Thread.new do
      sleep 0.02
      SolidQueue::Record.connection_pool.with_connection do
        create_ready_execution(queue_name: "critical", created_at: 5.seconds.ago)
        create_ready_execution(queue_name: "critical", created_at: 5.seconds.ago)
      end
      sleep 0.08
      SolidQueue::Record.connection_pool.with_connection do
        SolidQueue::Job.delete_all
      end
    end

    report = SolidLens::Runner.new.profile(duration: 0.3, sample_interval: 0.05)
    writer.join

    ready_backlog = report.evidence.fetch(:profile).fetch(:ready_backlog)

    assert_equal 0, ready_backlog.fetch(:finish_count)
    assert_equal 2, ready_backlog.fetch(:peak_count)
    assert_equal({"critical" => 2}, ready_backlog.fetch(:peak_by_queue))
    assert report.findings.any? { |finding| finding.id == "solid_queue.profile.ready_backlog.growing" }
  ensure
    writer&.join
  end
end
