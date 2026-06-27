# frozen_string_literal: true

module SolidLens
  module Collectors
    module ProfileEvidence
      class BloatSampleSet
        def initialize(samples:)
          @samples = samples
        end

        attr_reader :samples

        def error
          samples.each do |sample|
            bloat = payload(sample)
            return bloat[:error] if bloat[:error]
            return bloat["error"] if bloat["error"]
          end

          nil
        end

        def table_names
          samples.each_with_object([]) do |sample, result|
            tables(sample).each do |table_name, stats|
              result << table_name if active?(stats)
            end
          end.uniq.sort
        end

        def live_tuples(sample, table_name)
          stat(sample, table_name, :live_tuples, default: 0).to_i
        end

        def dead_tuples(sample, table_name)
          stat(sample, table_name, :dead_tuples, default: 0).to_i
        end

        def dead_tuple_ratio(sample, table_name)
          stat(sample, table_name, :dead_tuple_ratio, default: 0.0).to_f
        end

        private

        def payload(sample)
          value = sample.fetch(:evidence).fetch(:tables, {}).fetch(:bloat, {})
          value.is_a?(Hash) ? value : {}
        end

        def tables(sample)
          payload(sample).each_with_object({}) do |(table_name, stats), result|
            next if table_name == :error || table_name == "error"

            result[table_name] = stats
          end
        end

        def active?(stats)
          fetch_stat(stats, :dead_tuples, default: 0).to_i.positive? ||
            fetch_stat(stats, :dead_tuple_ratio, default: 0.0).to_f.positive?
        end

        def stat(sample, table_name, key, default:)
          fetch_stat(tables(sample).fetch(table_name, {}), key, default: default)
        end

        def fetch_stat(stats, key, default:)
          return default unless stats.is_a?(Hash)

          if stats.key?(key)
            stats.fetch(key)
          else
            stats.fetch(key.to_s, default)
          end
        end
      end
    end
  end
end
