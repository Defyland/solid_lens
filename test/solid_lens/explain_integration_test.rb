# frozen_string_literal: true

require "test_helper"

class ExplainIntegrationTest < SolidLensIntegrationCase
  def test_runner_explain_includes_structured_sqlite_plan_and_wildcard_query
    report = SolidLens::Runner.new.explain

    wildcard_query = report.evidence.fetch(:tables).fetch(:explains).fetch(:discover_wildcard_queues)

    assert_equal "sqlite", wildcard_query.fetch(:adapter)
    assert_match(/EXPLAIN QUERY PLAN/, wildcard_query.fetch(:explain_sql))
    assert_includes wildcard_query.fetch(:sql), "SELECT DISTINCT(queue_name)"
    assert wildcard_query.fetch(:rows).all? { |row| row.key?("detail") }
  end

  def test_runner_explain_includes_release_blocked_query_when_blocked_backlog_exists
    create_blocked_execution(
      queue_name: "critical",
      concurrency_key: "account:99",
      created_at: 10.minutes.ago,
      expires_at: 30.seconds.from_now
    )

    report = SolidLens::Runner.new.explain
    release_blocked = report.evidence.fetch(:tables).fetch(:explains).fetch(:release_blocked)

    assert_match(/solid_queue_blocked_executions/, release_blocked.fetch(:sql))
    assert_equal ["index_solid_queue_blocked_executions_for_release"], release_blocked.fetch(:expected_indexes)
  end
end
