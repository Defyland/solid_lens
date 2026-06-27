# frozen_string_literal: true

require "test_helper"

class CommandSurfaceIntegrationTest < SolidLensIntegrationCase
  def test_railtie_task_outputs_json_report
    output = SolidLens::TestSupport::RailsIntegration.with_env("FORMAT" => "json") do
      SolidLens::TestSupport::RailsIntegration.capture_stdout do
        Rake::Task["solid_lens:doctor"].reenable
        Rake::Task["solid_lens:doctor"].invoke
      end
    end

    report = JSON.parse(output)

    assert_equal "doctor", report.fetch("command")
    assert report.fetch("findings").any? { |finding| finding.fetch("id") == "solid_queue.pool.undersized" }
  end

  def test_railtie_task_fail_on_high_exits_non_zero
    output, error, status = capture_rake_task("doctor", env: {"FORMAT" => "json", "FAIL_ON_HIGH" => "1"})

    refute status.success?
    assert_equal 1, status.exitstatus
    assert_empty error

    report = JSON.parse(output)

    assert_equal "doctor", report.fetch("command")
  end

  def test_railtie_task_rejects_unknown_format_with_usage_exit
    output, error, status = capture_rake_task("doctor", env: {"FORMAT" => "xml"})

    refute status.success?
    assert_equal 64, status.exitstatus
    assert_empty output
    assert_includes error, 'solid_lens: unknown format "xml"; expected markdown or json'
  end

  def test_railtie_task_creates_parent_directories_for_output_file
    Dir.mktmpdir("solid-lens-rake-output") do |directory|
      output_path = File.join(directory, "nested/reports/solid_lens.json")
      output, error, status = capture_rake_task("doctor", env: {"FORMAT" => "json", "OUTPUT" => output_path})

      assert status.success?, error
      assert_empty error
      assert_empty output
      assert File.exist?(output_path)

      report = JSON.parse(File.read(output_path))

      assert_equal "doctor", report.fetch("command")
    end
  end

  def test_bin_rails_doctor_outputs_json_report
    output, error, status = SolidLens::TestSupport::RailsIntegration.capture_bin_rails(
      "solid_lens:doctor",
      "--format=json"
    )

    assert status.success?, error
    assert_empty error

    report = JSON.parse(output)

    assert_equal "doctor", report.fetch("command")
    assert report.fetch("findings").any? { |finding| finding.fetch("id") == "solid_queue.pool.undersized" }
  end

  def test_bin_rails_doctor_outputs_markdown_report_with_full_evidence
    output, error, status = SolidLens::TestSupport::RailsIntegration.capture_bin_rails(
      "solid_lens:doctor",
      "--format=markdown"
    )

    assert status.success?, error
    assert_empty error

    assert_includes output, "## Evidence"
    assert_includes output, "\"runtime\""
    assert_includes output, "\"database\""
    assert_includes output, "\"queue_config\""
    assert_includes output, "\"tables\""
  end

  def test_bin_rails_profile_accepts_long_options
    output, error, status = SolidLens::TestSupport::RailsIntegration.capture_bin_rails(
      "solid_lens:profile",
      "--duration=0",
      "--sample-interval=0.2",
      "--format=json"
    )

    assert status.success?, error
    assert_empty error

    report = JSON.parse(output)

    assert_equal "profile", report.fetch("command")
    assert_equal 0.2, report.fetch("evidence").fetch("profile").fetch("sample_interval_seconds")
  end

  def test_bin_rails_explain_outputs_json_report
    output, error, status = SolidLens::TestSupport::RailsIntegration.capture_bin_rails(
      "solid_lens:explain",
      "--format=json"
    )

    assert status.success?, error
    assert_empty error

    report = JSON.parse(output)

    assert_equal "explain", report.fetch("command")
    assert report.fetch("evidence").fetch("tables").fetch("explains").key?("poll_all")
  end

  def test_bin_rails_fail_on_high_returns_non_zero_for_high_findings
    output, error, status = SolidLens::TestSupport::RailsIntegration.capture_bin_rails(
      "solid_lens:doctor",
      "--format=json",
      "--fail-on-high"
    )

    refute status.success?
    assert_equal 1, status.exitstatus
    assert_empty error

    report = JSON.parse(output)

    assert_equal "doctor", report.fetch("command")
  end

  def test_bin_rails_rejects_unknown_format_with_usage_exit
    output, error, status = SolidLens::TestSupport::RailsIntegration.capture_bin_rails(
      "solid_lens:doctor",
      "--format=xml"
    )

    refute status.success?
    assert_equal 64, status.exitstatus
    assert_empty output
    assert_includes error, 'solid_lens: unknown format "xml"; expected markdown or json'
  end

  def test_bin_rails_creates_parent_directories_for_output_file
    Dir.mktmpdir("solid-lens-bin-rails-output") do |directory|
      output_path = File.join(directory, "nested/reports/solid_lens.json")
      output, error, status = SolidLens::TestSupport::RailsIntegration.capture_bin_rails(
        "solid_lens:doctor",
        "--format=json",
        "--output=#{output_path}"
      )

      assert status.success?, error
      assert_empty error
      assert_empty output
      assert File.exist?(output_path)

      report = JSON.parse(File.read(output_path))

      assert_equal "doctor", report.fetch("command")
    end
  end

  def test_cli_auto_bootstraps_rails_app_from_current_directory
    output, error, status = SolidLens::TestSupport::RailsIntegration.capture_cli(
      "doctor",
      "--format=json",
      "--rails-env=test"
    )

    assert status.success?, error
    assert_empty error

    report = JSON.parse(output)

    assert_equal "doctor", report.fetch("command")
    assert_equal "test", report.fetch("evidence").fetch("runtime").fetch("rails_env")
    assert_match(/\A\d+\.\d+\.\d+/, report.fetch("evidence").fetch("runtime").fetch("rails_version"))
    assert_equal true, report.fetch("evidence").fetch("database").fetch("connected")
    assert report.fetch("findings").any? { |finding| finding.fetch("id") == "solid_queue.pool.undersized" }
  end

  def test_cli_fail_on_high_returns_non_zero_for_high_findings
    output, error, status = SolidLens::TestSupport::RailsIntegration.capture_cli(
      "doctor",
      "--format=json",
      "--fail-on-high",
      "--rails-env=test"
    )

    refute status.success?
    assert_equal 1, status.exitstatus
    assert_empty error

    report = JSON.parse(output)

    assert_equal "doctor", report.fetch("command")
  end

  def test_cli_rejects_unknown_format_with_usage_exit
    output, error, status = SolidLens::TestSupport::RailsIntegration.capture_cli(
      "doctor",
      "--format=xml",
      "--rails-env=test"
    )

    refute status.success?
    assert_equal 64, status.exitstatus
    assert_empty output
    assert_includes error, 'solid_lens: unknown format "xml"; expected markdown or json'
  end

  def test_cli_creates_parent_directories_for_output_file
    Dir.mktmpdir("solid-lens-cli-output") do |directory|
      output_path = File.join(directory, "nested/reports/solid_lens.json")
      output, error, status = SolidLens::TestSupport::RailsIntegration.capture_cli(
        "doctor",
        "--format=json",
        "--output=#{output_path}",
        "--rails-env=test"
      )

      assert status.success?, error
      assert_empty error
      assert_empty output
      assert File.exist?(output_path)

      report = JSON.parse(File.read(output_path))

      assert_equal "doctor", report.fetch("command")
    end
  end
end
