# frozen_string_literal: true

require_relative "bloat_sample_set"

module SolidLens
  module Collectors
    module ProfileEvidence
      class BloatHealthBuilder
        def initialize(sample_set:)
          @sample_set = sample_set
        end

        def build
          if (error = bloat_sample_set.error)
            return {error: error, tables: {}}
          end

          {
            tables: bloat_sample_set.table_names.to_h do |table_name|
              [table_name, table_profile(table_name)]
            end
          }
        end

        private

        attr_reader :sample_set

        def table_profile(table_name)
          {
            start_live_tuples: start_live_tuples(table_name),
            finish_live_tuples: finish_live_tuples(table_name),
            live_tuple_delta: finish_live_tuples(table_name) - start_live_tuples(table_name),
            start_dead_tuples: start_dead_tuples(table_name),
            finish_dead_tuples: finish_dead_tuples(table_name),
            peak_dead_tuples: bloat_sample_set.dead_tuples(peak_dead_sample(table_name), table_name),
            peak_dead_tuples_at_seconds: sample_set.offset(peak_dead_sample(table_name)),
            dead_tuple_delta: finish_dead_tuples(table_name) - start_dead_tuples(table_name),
            dead_tuple_rate_per_second: sample_set.rate_per_second(finish_dead_tuples(table_name) - start_dead_tuples(table_name)),
            start_dead_tuple_ratio: start_dead_tuple_ratio(table_name),
            finish_dead_tuple_ratio: finish_dead_tuple_ratio(table_name),
            peak_dead_tuple_ratio: bloat_sample_set.dead_tuple_ratio(peak_ratio_sample(table_name), table_name),
            peak_dead_tuple_ratio_at_seconds: sample_set.offset(peak_ratio_sample(table_name)),
            dead_tuple_ratio_delta: (finish_dead_tuple_ratio(table_name) - start_dead_tuple_ratio(table_name)).round(4)
          }
        end

        def start_live_tuples(table_name)
          bloat_sample_set.live_tuples(first_sample, table_name)
        end

        def finish_live_tuples(table_name)
          bloat_sample_set.live_tuples(last_sample, table_name)
        end

        def start_dead_tuples(table_name)
          bloat_sample_set.dead_tuples(first_sample, table_name)
        end

        def finish_dead_tuples(table_name)
          bloat_sample_set.dead_tuples(last_sample, table_name)
        end

        def start_dead_tuple_ratio(table_name)
          bloat_sample_set.dead_tuple_ratio(first_sample, table_name)
        end

        def finish_dead_tuple_ratio(table_name)
          bloat_sample_set.dead_tuple_ratio(last_sample, table_name)
        end

        def peak_dead_sample(table_name)
          sample_set.peak_sample_for { |sample| bloat_sample_set.dead_tuples(sample, table_name) }
        end

        def peak_ratio_sample(table_name)
          sample_set.peak_sample_for { |sample| bloat_sample_set.dead_tuple_ratio(sample, table_name) }
        end

        def first_sample
          sample_set.samples.first
        end

        def last_sample
          sample_set.samples.last
        end

        def bloat_sample_set
          @bloat_sample_set ||= BloatSampleSet.new(samples: sample_set.samples)
        end
      end
    end
  end
end
