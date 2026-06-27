# frozen_string_literal: true

module SolidLens
  module Collectors
    module ProfileEvidence
      class ScheduledBacklogBuilder
        def initialize(sample_set:)
          @sample_set = sample_set
        end

        def build
          peak_sample = sample_set.peak_sample_for { |sample| overdue_scheduled_count(sample) }
          oldest_lag_sample = sample_set.peak_sample_for { |sample| oldest_scheduled_lag(sample) }
          start_overdue_count = sample_set.start_metric(:overdue_scheduled_count, default: 0).to_i
          finish_overdue_count = sample_set.finish_metric(:overdue_scheduled_count, default: 0).to_i
          overdue_count_delta = finish_overdue_count - start_overdue_count
          start_oldest_lag = sample_set.start_metric(:oldest_scheduled_lag_seconds, default: 0).to_f
          finish_oldest_lag = sample_set.finish_metric(:oldest_scheduled_lag_seconds, default: 0).to_f

          {
            start_overdue_count: start_overdue_count,
            finish_overdue_count: finish_overdue_count,
            peak_overdue_count: overdue_scheduled_count(peak_sample),
            peak_overdue_at_seconds: sample_set.offset(peak_sample),
            overdue_count_delta: overdue_count_delta,
            overdue_rate_per_second: sample_set.rate_per_second(overdue_count_delta),
            start_oldest_lag_seconds: start_oldest_lag,
            finish_oldest_lag_seconds: finish_oldest_lag,
            peak_oldest_lag_seconds: oldest_scheduled_lag(oldest_lag_sample),
            peak_oldest_lag_at_seconds: sample_set.offset(oldest_lag_sample),
            oldest_lag_delta_seconds: (finish_oldest_lag - start_oldest_lag).round(3),
            timeline: sample_set.samples.map do |sample|
              {
                offset_seconds: sample_set.offset(sample),
                overdue_count: overdue_scheduled_count(sample),
                oldest_lag_seconds: oldest_scheduled_lag(sample)
              }
            end
          }
        end

        private

        attr_reader :sample_set

        def overdue_scheduled_count(sample)
          sample_set.metric(sample, :overdue_scheduled_count, default: 0).to_i
        end

        def oldest_scheduled_lag(sample)
          sample_set.metric(sample, :oldest_scheduled_lag_seconds, default: 0).to_f
        end
      end
    end
  end
end
