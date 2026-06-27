# frozen_string_literal: true

module SolidLens
  module Collectors
    module ProfileEvidence
      class SemaphoreHealthBuilder
        SEMAPHORE_TABLE = "solid_queue_semaphores"

        def initialize(sample_set:)
          @sample_set = sample_set
        end

        def build
          {
            start_count: start_count,
            finish_count: finish_count,
            peak_count: semaphore_count(peak_count_sample),
            peak_count_at_seconds: sample_set.offset(peak_count_sample),
            count_delta: count_delta,
            count_rate_per_second: sample_set.rate_per_second(count_delta),
            start_expired_count: start_expired_count,
            finish_expired_count: finish_expired_count,
            peak_expired_count: expired_semaphore_count(peak_expired_count_sample),
            peak_expired_count_at_seconds: sample_set.offset(peak_expired_count_sample),
            expired_count_delta: expired_count_delta,
            expired_rate_per_second: sample_set.rate_per_second(expired_count_delta),
            start_oldest_expired_lag_seconds: start_oldest_expired_lag,
            finish_oldest_expired_lag_seconds: finish_oldest_expired_lag,
            peak_oldest_expired_lag_seconds: oldest_expired_semaphore_lag(peak_expired_lag_sample),
            peak_oldest_expired_lag_at_seconds: sample_set.offset(peak_expired_lag_sample),
            oldest_expired_lag_delta_seconds: (finish_oldest_expired_lag - start_oldest_expired_lag).round(3),
            start_expired_orphan_count: start_expired_orphan_count,
            finish_expired_orphan_count: finish_expired_orphan_count,
            peak_expired_orphan_count: expired_orphan_semaphore_count(peak_expired_orphan_count_sample),
            peak_expired_orphan_count_at_seconds: sample_set.offset(peak_expired_orphan_count_sample),
            expired_orphan_count_delta: expired_orphan_count_delta,
            expired_orphan_rate_per_second: sample_set.rate_per_second(expired_orphan_count_delta),
            start_oldest_expired_orphan_lag_seconds: start_oldest_expired_orphan_lag,
            finish_oldest_expired_orphan_lag_seconds: finish_oldest_expired_orphan_lag,
            peak_oldest_expired_orphan_lag_seconds: oldest_expired_orphan_semaphore_lag(peak_expired_orphan_lag_sample),
            peak_oldest_expired_orphan_lag_at_seconds: sample_set.offset(peak_expired_orphan_lag_sample),
            oldest_expired_orphan_lag_delta_seconds: (finish_oldest_expired_orphan_lag - start_oldest_expired_orphan_lag).round(3),
            finish_expired_orphan_keys: sample_set.finish_array_metric(:expired_orphan_semaphore_keys),
            peak_expired_orphan_keys: sample_set.array_metric(peak_expired_orphan_count_sample, :expired_orphan_semaphore_keys),
            timeline: sample_set.samples.map { |sample| timeline_entry(sample) }
          }
        end

        private

        attr_reader :sample_set

        def peak_count_sample
          @peak_count_sample ||= sample_set.peak_sample_for { |sample| semaphore_count(sample) }
        end

        def peak_expired_count_sample
          @peak_expired_count_sample ||= sample_set.peak_sample_for { |sample| expired_semaphore_count(sample) }
        end

        def peak_expired_lag_sample
          @peak_expired_lag_sample ||= sample_set.peak_sample_for { |sample| oldest_expired_semaphore_lag(sample) }
        end

        def peak_expired_orphan_count_sample
          @peak_expired_orphan_count_sample ||= sample_set.peak_sample_for { |sample| expired_orphan_semaphore_count(sample) }
        end

        def peak_expired_orphan_lag_sample
          @peak_expired_orphan_lag_sample ||= sample_set.peak_sample_for { |sample| oldest_expired_orphan_semaphore_lag(sample) }
        end

        def start_count
          @start_count ||= sample_set.start_count(SEMAPHORE_TABLE)
        end

        def finish_count
          @finish_count ||= sample_set.finish_count(SEMAPHORE_TABLE)
        end

        def count_delta
          @count_delta ||= finish_count - start_count
        end

        def start_expired_count
          @start_expired_count ||= sample_set.start_metric(:expired_semaphore_count, default: 0).to_i
        end

        def finish_expired_count
          @finish_expired_count ||= sample_set.finish_metric(:expired_semaphore_count, default: 0).to_i
        end

        def expired_count_delta
          @expired_count_delta ||= finish_expired_count - start_expired_count
        end

        def start_oldest_expired_lag
          @start_oldest_expired_lag ||= sample_set.start_metric(:oldest_expired_semaphore_lag_seconds, default: 0).to_f
        end

        def finish_oldest_expired_lag
          @finish_oldest_expired_lag ||= sample_set.finish_metric(:oldest_expired_semaphore_lag_seconds, default: 0).to_f
        end

        def start_expired_orphan_count
          @start_expired_orphan_count ||= sample_set.start_metric(:expired_orphan_semaphore_count, default: 0).to_i
        end

        def finish_expired_orphan_count
          @finish_expired_orphan_count ||= sample_set.finish_metric(:expired_orphan_semaphore_count, default: 0).to_i
        end

        def expired_orphan_count_delta
          @expired_orphan_count_delta ||= finish_expired_orphan_count - start_expired_orphan_count
        end

        def start_oldest_expired_orphan_lag
          @start_oldest_expired_orphan_lag ||= sample_set.start_metric(:oldest_expired_orphan_semaphore_lag_seconds, default: 0).to_f
        end

        def finish_oldest_expired_orphan_lag
          @finish_oldest_expired_orphan_lag ||= sample_set.finish_metric(:oldest_expired_orphan_semaphore_lag_seconds, default: 0).to_f
        end

        def timeline_entry(sample)
          {
            offset_seconds: sample_set.offset(sample),
            count: semaphore_count(sample),
            expired_count: expired_semaphore_count(sample),
            oldest_expired_lag_seconds: oldest_expired_semaphore_lag(sample),
            expired_orphan_count: expired_orphan_semaphore_count(sample),
            oldest_expired_orphan_lag_seconds: oldest_expired_orphan_semaphore_lag(sample)
          }
        end

        def semaphore_count(sample)
          sample_set.count(sample, SEMAPHORE_TABLE)
        end

        def expired_semaphore_count(sample)
          sample_set.metric(sample, :expired_semaphore_count, default: 0).to_i
        end

        def oldest_expired_semaphore_lag(sample)
          sample_set.metric(sample, :oldest_expired_semaphore_lag_seconds, default: 0).to_f
        end

        def expired_orphan_semaphore_count(sample)
          sample_set.metric(sample, :expired_orphan_semaphore_count, default: 0).to_i
        end

        def oldest_expired_orphan_semaphore_lag(sample)
          sample_set.metric(sample, :oldest_expired_orphan_semaphore_lag_seconds, default: 0).to_f
        end
      end
    end
  end
end
