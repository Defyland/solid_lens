# frozen_string_literal: true

module SolidLens
  module Collectors
    module ProfileEvidence
      class BlockedBacklogBuilder
        BLOCKED_TABLE = "solid_queue_blocked_executions"
        BLOCKED_QUEUE_DEPTH_KEY = :blocked_queue_depth_by_queue

        def initialize(sample_set:)
          @sample_set = sample_set
        end

        def build
          peak_count_sample = sample_set.peak_sample_for { |sample| blocked_count(sample) }
          peak_oldest_age_sample = sample_set.peak_sample_for { |sample| blocked_oldest_age(sample) }
          peak_expired_count_sample = sample_set.peak_sample_for { |sample| expired_blocked_count(sample) }
          peak_expired_lag_sample = sample_set.peak_sample_for { |sample| oldest_expired_blocked_lag(sample) }
          start_count = sample_set.start_count(BLOCKED_TABLE)
          finish_count = sample_set.finish_count(BLOCKED_TABLE)
          count_delta = finish_count - start_count
          start_oldest_age = sample_set.start_metric(:oldest_blocked_age_seconds, default: 0).to_f
          finish_oldest_age = sample_set.finish_metric(:oldest_blocked_age_seconds, default: 0).to_f
          start_expired_count = sample_set.start_metric(:expired_blocked_execution_count, default: 0).to_i
          finish_expired_count = sample_set.finish_metric(:expired_blocked_execution_count, default: 0).to_i
          expired_count_delta = finish_expired_count - start_expired_count
          start_oldest_expired_lag = sample_set.start_metric(:oldest_expired_blocked_lag_seconds, default: 0).to_f
          finish_oldest_expired_lag = sample_set.finish_metric(:oldest_expired_blocked_lag_seconds, default: 0).to_f
          start_by_queue = sample_set.start_hash_metric(BLOCKED_QUEUE_DEPTH_KEY)
          finish_by_queue = sample_set.finish_hash_metric(BLOCKED_QUEUE_DEPTH_KEY)

          {
            start_count: start_count,
            finish_count: finish_count,
            peak_count: blocked_count(peak_count_sample),
            peak_count_at_seconds: sample_set.offset(peak_count_sample),
            count_delta: count_delta,
            count_rate_per_second: sample_set.rate_per_second(count_delta),
            start_oldest_age_seconds: start_oldest_age,
            finish_oldest_age_seconds: finish_oldest_age,
            peak_oldest_age_seconds: blocked_oldest_age(peak_oldest_age_sample),
            peak_oldest_age_at_seconds: sample_set.offset(peak_oldest_age_sample),
            oldest_age_delta_seconds: (finish_oldest_age - start_oldest_age).round(3),
            start_expired_count: start_expired_count,
            finish_expired_count: finish_expired_count,
            peak_expired_count: expired_blocked_count(peak_expired_count_sample),
            peak_expired_count_at_seconds: sample_set.offset(peak_expired_count_sample),
            expired_count_delta: expired_count_delta,
            expired_rate_per_second: sample_set.rate_per_second(expired_count_delta),
            start_oldest_expired_lag_seconds: start_oldest_expired_lag,
            finish_oldest_expired_lag_seconds: finish_oldest_expired_lag,
            peak_oldest_expired_lag_seconds: oldest_expired_blocked_lag(peak_expired_lag_sample),
            peak_oldest_expired_lag_at_seconds: sample_set.offset(peak_expired_lag_sample),
            oldest_expired_lag_delta_seconds: (finish_oldest_expired_lag - start_oldest_expired_lag).round(3),
            start_by_queue: start_by_queue,
            finish_by_queue: finish_by_queue,
            peak_by_queue: sample_set.peak_hash_metric(BLOCKED_QUEUE_DEPTH_KEY),
            queue_deltas: sample_set.queue_deltas(start_by_queue, finish_by_queue),
            timeline: sample_set.samples.map do |sample|
              {
                offset_seconds: sample_set.offset(sample),
                count: blocked_count(sample),
                expired_count: expired_blocked_count(sample),
                oldest_age_seconds: blocked_oldest_age(sample),
                oldest_expired_lag_seconds: oldest_expired_blocked_lag(sample)
              }
            end
          }
        end

        private

        attr_reader :sample_set

        def blocked_count(sample)
          sample_set.count(sample, BLOCKED_TABLE)
        end

        def blocked_oldest_age(sample)
          sample_set.metric(sample, :oldest_blocked_age_seconds, default: 0).to_f
        end

        def expired_blocked_count(sample)
          sample_set.metric(sample, :expired_blocked_execution_count, default: 0).to_i
        end

        def oldest_expired_blocked_lag(sample)
          sample_set.metric(sample, :oldest_expired_blocked_lag_seconds, default: 0).to_f
        end
      end
    end
  end
end
