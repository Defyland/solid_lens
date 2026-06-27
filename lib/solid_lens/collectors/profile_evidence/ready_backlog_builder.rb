# frozen_string_literal: true

module SolidLens
  module Collectors
    module ProfileEvidence
      class ReadyBacklogBuilder
        READY_TABLE = "solid_queue_ready_executions"
        READY_QUEUE_DEPTH_KEY = :ready_queue_depth_by_queue

        def initialize(sample_set:)
          @sample_set = sample_set
        end

        def build
          peak_sample = sample_set.peak_sample_for { |sample| ready_count(sample) }
          oldest_age_sample = sample_set.peak_sample_for { |sample| ready_oldest_age(sample) }
          start_by_queue = sample_set.start_hash_metric(READY_QUEUE_DEPTH_KEY)
          finish_by_queue = sample_set.finish_hash_metric(READY_QUEUE_DEPTH_KEY)
          start_count = sample_set.start_count(READY_TABLE)
          finish_count = sample_set.finish_count(READY_TABLE)
          delta = finish_count - start_count
          start_oldest_age = sample_set.start_metric(:oldest_ready_age_seconds, default: 0).to_f
          finish_oldest_age = sample_set.finish_metric(:oldest_ready_age_seconds, default: 0).to_f

          {
            start_count: start_count,
            finish_count: finish_count,
            peak_count: ready_count(peak_sample),
            peak_count_at_seconds: sample_set.offset(peak_sample),
            delta: delta,
            rate_per_second: sample_set.rate_per_second(delta),
            start_oldest_age_seconds: start_oldest_age,
            finish_oldest_age_seconds: finish_oldest_age,
            peak_oldest_age_seconds: ready_oldest_age(oldest_age_sample),
            peak_oldest_age_at_seconds: sample_set.offset(oldest_age_sample),
            oldest_age_delta_seconds: (finish_oldest_age - start_oldest_age).round(3),
            start_by_queue: start_by_queue,
            finish_by_queue: finish_by_queue,
            peak_by_queue: sample_set.peak_hash_metric(READY_QUEUE_DEPTH_KEY),
            queue_deltas: sample_set.queue_deltas(start_by_queue, finish_by_queue),
            timeline: sample_set.samples.map do |sample|
              {
                offset_seconds: sample_set.offset(sample),
                count: ready_count(sample),
                oldest_age_seconds: ready_oldest_age(sample)
              }
            end
          }
        end

        private

        attr_reader :sample_set

        def ready_count(sample)
          sample_set.count(sample, READY_TABLE)
        end

        def ready_oldest_age(sample)
          sample_set.metric(sample, :oldest_ready_age_seconds, default: 0).to_f
        end
      end
    end
  end
end
