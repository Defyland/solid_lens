# frozen_string_literal: true

module SolidLens
  class Finding
    SEVERITIES = %i[critical high medium low info].freeze

    attr_reader :id, :severity, :title, :evidence, :recommendation

    def initialize(id:, severity:, title:, recommendation:, evidence: {})
      severity = severity.to_sym
      raise ArgumentError, "unknown severity: #{severity}" unless SEVERITIES.include?(severity)

      @id = id
      @severity = severity
      @title = title
      @evidence = evidence.freeze
      @recommendation = recommendation
      freeze
    end

    def to_h
      {
        id: id,
        severity: severity,
        title: title,
        evidence: evidence,
        recommendation: recommendation
      }
    end
  end
end
