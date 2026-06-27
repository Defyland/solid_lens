# frozen_string_literal: true

require "test_helper"

class QueueSurfacePathologyChecksTest < Minitest::Test
  def test_wildcard_queue_check_escalates_for_large_ready_table
    findings = SolidLens::Checks::WildcardQueuesCheck.new(
      queue_config: {wildcard_queue_specs: ["critical*"]},
      database: {},
      tables: {counts: {"solid_queue_ready_executions" => 20_000}}
    ).call

    assert_equal :high, findings.fetch(0).severity
  end

  def test_wildcard_queue_check_is_medium_for_smaller_ready_tables
    findings = SolidLens::Checks::WildcardQueuesCheck.new(
      queue_config: {wildcard_queue_specs: ["critical*"]},
      database: {},
      tables: {counts: {"solid_queue_ready_executions" => 500}}
    ).call

    finding = findings.fetch(0)

    assert_equal "solid_queue.queues.wildcard", finding.id
    assert_equal :medium, finding.severity
    assert_equal ["critical*"], finding.evidence.fetch(:wildcard_queue_specs)
  end

  def test_paused_queues_check_flags_paused_queues
    findings = SolidLens::Checks::PausedQueuesCheck.new(
      queue_config: {},
      database: {},
      tables: {paused_queues: ["mailers"]}
    ).call

    finding = findings.fetch(0)

    assert_equal "solid_queue.queues.paused", finding.id
    assert_equal :medium, finding.severity
    assert_equal ["mailers"], finding.evidence.fetch(:paused_queues)
  end

  def test_scheduled_jobs_check_flags_overdue_jobs
    findings = SolidLens::Checks::ScheduledJobsCheck.new(
      queue_config: {},
      database: {},
      tables: {overdue_scheduled_count: 2, overdue_scheduled_grace_seconds: 60}
    ).call

    finding = findings.fetch(0)

    assert_equal "solid_queue.scheduled.overdue", finding.id
    assert_equal 60, finding.evidence.fetch(:overdue_scheduled_grace_seconds)
  end
end
