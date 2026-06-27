# frozen_string_literal: true

require "test_helper"
require "json"

class ReportersTest < Minitest::Test
  def test_json_reporter_is_machine_readable
    report = SolidLens::Report.new(
      command: "doctor",
      evidence: {},
      findings: [
        SolidLens::Finding.new(id: "x", severity: :high, title: "X", recommendation: "Fix")
      ],
      generated_at: Time.utc(2026, 6, 13)
    )

    parsed = JSON.parse(SolidLens::Reporters::JsonReporter.new(report).render)

    assert_equal "doctor", parsed.fetch("command")
    assert_equal 1, parsed.fetch("summary").fetch("high")
  end

  def test_markdown_reporter_lists_findings_and_full_evidence
    report = SolidLens::Report.new(
      command: "doctor",
      evidence: {runtime: {rails_env: "production"}},
      findings: [
        SolidLens::Finding.new(id: "x", severity: :high, title: "X", recommendation: "Fix")
      ],
      generated_at: Time.utc(2026, 6, 13)
    )

    rendered = SolidLens::Reporters::MarkdownReporter.new(report).render

    assert_includes rendered, "# SolidLens doctor"
    assert_includes rendered, "## Evidence"
    assert_includes rendered, "\"rails_env\": \"production\""
    assert_includes rendered, "HIGH: X"
    assert_includes rendered, "```json"
  end

  def test_markdown_reporter_renders_profile_evidence_inside_evidence_section
    report = SolidLens::Report.new(
      command: "profile",
      evidence: {profile: {duration_seconds: 60, ready_backlog: {delta: 2}}},
      findings: [],
      generated_at: Time.utc(2026, 6, 13)
    )

    rendered = SolidLens::Reporters::MarkdownReporter.new(report).render

    assert_includes rendered, "## Evidence"
    assert_includes rendered, "\"profile\""
    assert_includes rendered, "\"duration_seconds\": 60"
  end
end
