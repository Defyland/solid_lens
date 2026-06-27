# frozen_string_literal: true

module SolidLens
  module Collectors
    module ProfileEvidence
      class SampleSet
        def initialize(samples:, duration:)
          @samples = samples
          @duration = duration.to_f
        end

        attr_reader :samples

        def table_count_delta
          finish_counts.to_h do |table, count|
            [table, count.to_i - start_counts.fetch(table, 0).to_i]
          end
        end

        def table_count_rate_per_second
          finish_counts.to_h do |table, count|
            delta = count.to_i - start_counts.fetch(table, 0).to_i
            [table, rate_per_second(delta)]
          end
        end

        def peak_sample_for
          samples.max_by { |sample| yield(sample).to_f } || first_sample
        end

        def queue_deltas(start_by_queue, finish_by_queue)
          (start_by_queue.keys | finish_by_queue.keys).sort.each_with_object({}) do |queue_name, result|
            delta = finish_by_queue.fetch(queue_name, 0).to_i - start_by_queue.fetch(queue_name, 0).to_i
            result[queue_name] = delta unless delta.zero?
          end
        end

        def rate_per_second(delta)
          return nil unless duration.positive?

          (delta.to_f / duration).round(3)
        end

        def offset(sample)
          sample.fetch(:offset_seconds)
        end

        def count(sample, table_name)
          counts(sample).fetch(table_name, 0).to_i
        end

        def start_count(table_name)
          start_counts.fetch(table_name, 0).to_i
        end

        def finish_count(table_name)
          finish_counts.fetch(table_name, 0).to_i
        end

        def metric(sample, key, default: 0)
          value = tables(sample).fetch(key, default)
          value.nil? ? default : value
        end

        def start_metric(key, default: 0)
          metric(first_sample, key, default: default)
        end

        def finish_metric(key, default: 0)
          metric(last_sample, key, default: default)
        end

        def hash_metric(sample, key)
          value = tables(sample).fetch(key, {})
          value.is_a?(Hash) ? value : {}
        end

        def start_hash_metric(key)
          hash_metric(first_sample, key)
        end

        def finish_hash_metric(key)
          hash_metric(last_sample, key)
        end

        def array_metric(sample, key)
          Array(tables(sample).fetch(key, []))
        end

        def start_array_metric(key)
          array_metric(first_sample, key)
        end

        def finish_array_metric(key)
          array_metric(last_sample, key)
        end

        def peak_hash_metric(key)
          samples.each_with_object({}) do |sample, result|
            hash_metric(sample, key).each do |name, count|
              result[name] = [result.fetch(name, 0).to_i, count.to_i].max
            end
          end
        end

        private

        attr_reader :duration

        def first_sample
          samples.first
        end

        def last_sample
          samples.last
        end

        def start_counts
          @start_counts ||= counts(first_sample)
        end

        def finish_counts
          @finish_counts ||= counts(last_sample)
        end

        def tables(sample)
          sample.fetch(:evidence).fetch(:tables, {})
        end

        def counts(sample)
          tables(sample).fetch(:counts, {})
        end
      end
    end
  end
end
