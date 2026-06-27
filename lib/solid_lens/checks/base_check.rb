# frozen_string_literal: true

module SolidLens
  module Checks
    class BaseCheck
      def initialize(evidence)
        @evidence = evidence
      end

      private

      attr_reader :evidence

      def finding(id:, severity:, title:, evidence:, recommendation:)
        Finding.new(
          id: id,
          severity: severity,
          title: title,
          evidence: evidence,
          recommendation: recommendation
        )
      end

      def queue_config
        evidence.fetch(:queue_config, {})
      end

      def runtime
        evidence.fetch(:runtime, {})
      end

      def database
        evidence.fetch(:database, {})
      end

      def tables
        evidence.fetch(:tables, {})
      end

      def profile
        evidence.fetch(:profile, {})
      end
    end
  end
end
