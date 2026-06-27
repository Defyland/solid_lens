# frozen_string_literal: true

module SolidLens
  module Collectors
    module ProfileEvidence
      class ClaimedExecutionHealthBuilder
        def initialize(sample_set:)
          @sample_set = sample_set
        end

        def build
          {
            process_alive_threshold_seconds: sample_set.finish_metric(:process_alive_threshold_seconds, default: nil),
            start_dead_count: start_dead_count,
            finish_dead_count: finish_dead_count,
            peak_dead_count: claimed_dead_count(peak_dead_count_sample),
            peak_dead_count_at_seconds: sample_set.offset(peak_dead_count_sample),
            dead_count_delta: dead_count_delta,
            dead_rate_per_second: sample_set.rate_per_second(dead_count_delta),
            start_oldest_dead_lag_seconds: start_oldest_dead_lag,
            finish_oldest_dead_lag_seconds: finish_oldest_dead_lag,
            peak_oldest_dead_lag_seconds: oldest_claimed_dead_lag(peak_dead_lag_sample),
            peak_oldest_dead_lag_at_seconds: sample_set.offset(peak_dead_lag_sample),
            oldest_dead_lag_delta_seconds: (finish_oldest_dead_lag - start_oldest_dead_lag).round(3),
            timeline: sample_set.samples.map { |sample| timeline_entry(sample) }
          }
        end

        private

        attr_reader :sample_set

        def peak_dead_count_sample
          @peak_dead_count_sample ||= sample_set.peak_sample_for { |sample| claimed_dead_count(sample) }
        end

        def peak_dead_lag_sample
          @peak_dead_lag_sample ||= sample_set.peak_sample_for { |sample| oldest_claimed_dead_lag(sample) }
        end

        def start_dead_count
          @start_dead_count ||= sample_set.start_metric(:claimed_by_dead_process_count, default: 0).to_i
        end

        def finish_dead_count
          @finish_dead_count ||= sample_set.finish_metric(:claimed_by_dead_process_count, default: 0).to_i
        end

        def dead_count_delta
          @dead_count_delta ||= finish_dead_count - start_dead_count
        end

        def start_oldest_dead_lag
          @start_oldest_dead_lag ||= sample_set.start_metric(:oldest_claimed_dead_lag_seconds, default: 0).to_f
        end

        def finish_oldest_dead_lag
          @finish_oldest_dead_lag ||= sample_set.finish_metric(:oldest_claimed_dead_lag_seconds, default: 0).to_f
        end

        def timeline_entry(sample)
          {
            offset_seconds: sample_set.offset(sample),
            dead_count: claimed_dead_count(sample),
            oldest_dead_lag_seconds: oldest_claimed_dead_lag(sample)
          }
        end

        def claimed_dead_count(sample)
          sample_set.metric(sample, :claimed_by_dead_process_count, default: 0).to_i
        end

        def oldest_claimed_dead_lag(sample)
          sample_set.metric(sample, :oldest_claimed_dead_lag_seconds, default: 0).to_f
        end
      end
    end
  end
end
