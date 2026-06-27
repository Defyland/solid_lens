# frozen_string_literal: true

module SolidLens
  class Report
    attr_reader :command, :generated_at, :evidence, :findings

    def initialize(command:, evidence:, findings:, generated_at: Time.now.utc)
      @command = command
      @generated_at = generated_at
      @evidence = evidence
      @findings = findings
    end

    def exit_status
      (findings.any? { |finding| %i[critical high].include?(finding.severity) }) ? 1 : 0
    end

    def to_h
      {
        command: command,
        generated_at: generated_at.iso8601,
        summary: summary,
        evidence: evidence,
        findings: findings.map(&:to_h)
      }
    end

    def summary
      counts = Hash.new(0)
      findings.each { |finding| counts[finding.severity] += 1 }
      Finding::SEVERITIES.to_h { |severity| [severity, counts[severity]] }
    end
  end
end
