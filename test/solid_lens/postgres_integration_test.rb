# frozen_string_literal: true

require "test_helper"

class PostgresIntegrationTest < Minitest::Test
  def setup
    skip "PostgreSQL test support unavailable" unless SolidLens::TestSupport::LocalPostgresServer.available?

    @postgres = SolidLens::TestSupport::LocalPostgresServer.new.start
    _stdout, stderr, status = SolidLens::TestSupport::RailsIntegration.prepare_schema_via_subprocess(env: @postgres.env)
    assert status.success?, stderr
  end

  def teardown
    @postgres&.stop
  end

  def test_cli_reports_postgresql_evidence_and_json_explain_output
    output, error, status = SolidLens::TestSupport::RailsIntegration.capture_cli(
      "doctor",
      "--format=json",
      "--rails-env=test",
      env: @postgres.env
    )

    assert status.success?, error
    assert_empty error

    report = JSON.parse(output)

    assert_equal true, report.dig("evidence", "database", "connected")
    assert_equal "PostgreSQL", report.dig("evidence", "database", "adapter_name")
    assert_equal true, report.dig("evidence", "database", "skip_locked_supported")
    assert report.fetch("findings").any? { |finding| finding.fetch("id") == "solid_queue.pool.undersized" }

    explain_output, explain_error, explain_status = SolidLens::TestSupport::RailsIntegration.capture_cli(
      "explain",
      "--format=json",
      "--rails-env=test",
      env: @postgres.env
    )

    assert explain_status.success?, explain_error
    assert_empty explain_error

    explain_report = JSON.parse(explain_output)
    poll_all = explain_report.dig("evidence", "tables", "explains", "poll_all")

    assert_equal "postgresql", poll_all.fetch("adapter")
    assert_match(/EXPLAIN \(FORMAT JSON\)/, poll_all.fetch("explain_sql"))
    assert_equal ["index_solid_queue_poll_all"], poll_all.fetch("expected_indexes")
    assert poll_all.fetch("rows").all? { |row| row.key?("QUERY PLAN") }
    assert_kind_of Hash, explain_report.dig("evidence", "tables", "bloat")

    profile_output, profile_error, profile_status = SolidLens::TestSupport::RailsIntegration.capture_cli(
      "profile",
      "--duration=0",
      "--format=json",
      "--rails-env=test",
      env: @postgres.env
    )

    assert profile_status.success?, profile_error
    assert_empty profile_error

    profile_report = JSON.parse(profile_output)

    assert_kind_of Hash, profile_report.dig("evidence", "profile", "bloat_health", "tables")
  end
end
