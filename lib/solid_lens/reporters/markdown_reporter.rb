# frozen_string_literal: true

require "json"

module SolidLens
  module Reporters
    class MarkdownReporter
      def initialize(report)
        @report = report
      end

      def render
        lines = [
          "# SolidLens #{@report.command}",
          "",
          "Generated at: #{@report.generated_at.iso8601}",
          "",
          "## Summary"
        ]

        @report.summary.each do |severity, count|
          lines << "- #{severity}: #{count}"
        end

        lines << ""
        lines << "## Evidence"
        lines << ""
        lines << "```json"
        lines << JSON.pretty_generate(@report.evidence)
        lines << "```"
        lines << ""
        lines << "## Findings"

        if @report.findings.empty?
          lines << ""
          lines << "No findings."
        else
          @report.findings.each do |finding|
            lines << ""
            lines << "### #{finding.severity.to_s.upcase}: #{finding.title}"
            lines << ""
            lines << "- id: `#{finding.id}`"
            lines << "- evidence:"
            lines << ""
            lines << "```json"
            lines << JSON.pretty_generate(finding.evidence)
            lines << "```"
            lines << "- recommendation: #{finding.recommendation}"
          end
        end

        lines << ""
        lines.join("\n")
      end
    end
  end
end
