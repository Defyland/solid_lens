# frozen_string_literal: true

require_relative "profile_evidence/execution_state_builder"
require_relative "profile_evidence/maintenance_health_builder"
require_relative "profile_evidence/sample_set"

module SolidLens
  module Collectors
    class ProfileEvidenceBuilder
      def initialize(samples:, duration:, requested_sample_interval:, effective_sample_interval:, max_samples:)
        @samples = samples
        @duration = duration.to_f
        @requested_sample_interval = requested_sample_interval.to_f
        @effective_sample_interval = effective_sample_interval.to_f
        @max_samples = max_samples.to_i
      end

      def build
        {
          duration_seconds: duration,
          requested_sample_interval_seconds: requested_sample_interval.round(3),
          sample_interval_seconds: effective_sample_interval.round(3),
          sample_limit_applied: effective_sample_interval > requested_sample_interval,
          max_samples: max_samples,
          sample_count: samples.size,
          table_count_delta: sample_set.table_count_delta,
          table_count_rate_per_second: sample_set.table_count_rate_per_second
        }.merge(execution_state_builder.build)
          .merge(maintenance_health_builder.build)
      end

      private

      attr_reader :duration, :effective_sample_interval, :max_samples, :requested_sample_interval, :samples

      def sample_set
        @sample_set ||= ProfileEvidence::SampleSet.new(samples: samples, duration: duration)
      end

      def execution_state_builder
        @execution_state_builder ||= ProfileEvidence::ExecutionStateBuilder.new(sample_set: sample_set)
      end

      def maintenance_health_builder
        @maintenance_health_builder ||= ProfileEvidence::MaintenanceHealthBuilder.new(sample_set: sample_set)
      end
    end
  end
end
