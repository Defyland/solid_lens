# frozen_string_literal: true

require_relative "profile_evidence_builder"

module SolidLens
  module Collectors
    class ProfileCollector
      DEFAULT_SAMPLE_INTERVAL = 5.0
      DEFAULT_MAX_SAMPLES = 240

      def initialize(evidence_collector:, duration:, sample_interval: DEFAULT_SAMPLE_INTERVAL, max_samples: DEFAULT_MAX_SAMPLES, sleeper: Kernel.method(:sleep), monotonic_clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
        @evidence_collector = evidence_collector
        @duration = duration.to_f
        @sample_interval = sample_interval.to_f
        @max_samples = [max_samples.to_i, 2].max
        @sleeper = sleeper
        @monotonic_clock = monotonic_clock
      end

      def collect
        start_time = monotonic_clock.call
        samples = [sample(offset_seconds: 0.0, evidence: evidence_collector.call)]
        next_offset = effective_sample_interval

        while next_offset < duration
          sleep_until_offset(start_time, next_offset)
          samples << collect_sample(start_time)
          next_offset += effective_sample_interval
        end

        collect_final_sample(start_time, samples) if duration.positive?

        finish_evidence = samples.last.fetch(:evidence)

        {
          evidence: finish_evidence,
          profile: ProfileEvidenceBuilder.new(
            samples: samples,
            duration: duration,
            requested_sample_interval: requested_sample_interval,
            effective_sample_interval: effective_sample_interval,
            max_samples: max_samples
          ).build
        }
      end

      private

      attr_reader :duration, :evidence_collector, :max_samples, :monotonic_clock, :sample_interval, :sleeper

      def sample(offset_seconds:, evidence:)
        {
          offset_seconds: offset_seconds.round(3),
          evidence: evidence
        }
      end

      def collect_sample(start_time)
        sample(offset_seconds: elapsed_since(start_time), evidence: evidence_collector.call)
      end

      def collect_final_sample(start_time, samples)
        last_offset = samples.last.fetch(:offset_seconds)
        return if last_offset >= duration.round(3)

        sleep_until_offset(start_time, duration)
        samples << collect_sample(start_time)
      end

      def elapsed_since(start_time)
        (monotonic_clock.call - start_time).to_f
      end

      def sleep_until_offset(start_time, target_offset)
        remaining = target_offset - elapsed_since(start_time)
        sleeper.call(remaining) if remaining.positive?
      end

      def effective_sample_interval
        @effective_sample_interval ||= begin
          requested = requested_sample_interval
          return requested unless duration.positive?

          [requested, minimum_sample_interval_for_limit].max
        end
      end

      def requested_sample_interval
        @requested_sample_interval ||= sample_interval.positive? ? sample_interval : DEFAULT_SAMPLE_INTERVAL
      end

      def minimum_sample_interval_for_limit
        duration.to_f / (max_samples - 1)
      end
    end
  end
end
