# frozen_string_literal: true

require "test_helper"

class MariaDbIntegrationTest < Minitest::Test
  DATABASE_URL_ENV = "SOLID_LENS_TEST_MARIADB_DATABASE_URL"

  def setup
    skip "MariaDB integration URL unavailable" if database_url.empty?

    _stdout, stderr, status = SolidLens::TestSupport::RailsIntegration.prepare_schema_via_subprocess(env: integration_env)
    assert status.success?, stderr
  end

  def test_cli_reports_mariadb_evidence_and_mysql_style_explain_output
    output, error, status = SolidLens::TestSupport::RailsIntegration.capture_cli(
      "doctor",
      "--format=json",
      "--rails-env=test",
      env: integration_env
    )

    assert status.success?, error
    assert_empty error

    report = JSON.parse(output)

    assert_equal true, report.dig("evidence", "database", "connected")
    assert_equal "Trilogy", report.dig("evidence", "database", "adapter_name")
    assert_includes report.dig("evidence", "database", "database_version").downcase, "mariadb"
    assert_equal true, report.dig("evidence", "database", "skip_locked_supported")
    assert report.fetch("findings").any? { |finding| finding.fetch("id") == "solid_queue.pool.undersized" }

    explain_output, explain_error, explain_status = SolidLens::TestSupport::RailsIntegration.capture_cli(
      "explain",
      "--format=json",
      "--rails-env=test",
      env: integration_env
    )

    assert explain_status.success?, explain_error
    assert_empty explain_error

    explain_report = JSON.parse(explain_output)
    poll_all = explain_report.dig("evidence", "tables", "explains", "poll_all")

    assert_equal "trilogy", poll_all.fetch("adapter")
    assert_match(/\AEXPLAIN /, poll_all.fetch("explain_sql"))
    assert_equal ["index_solid_queue_poll_all"], poll_all.fetch("expected_indexes")
    assert poll_all.fetch("rows").all? { |row| row.key?("type") && row.key?("key") }
  end

  private

  def database_url
    ENV.fetch(DATABASE_URL_ENV, "").strip
  end

  def integration_env
    {"SOLID_LENS_TEST_DATABASE_URL" => database_url}
  end
end
