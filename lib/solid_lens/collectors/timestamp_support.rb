# frozen_string_literal: true

module SolidLens
  module Collectors
    module TimestampSupport
      private

      def timestamp_age_seconds(now:, value:)
        return 0.0 if value.nil?

        timestamp = parse_timestamp(value)
        [(now - timestamp).to_f, 0.0].max.round(3)
      rescue
        0.0
      end

      def parse_timestamp(value)
        return if value.nil?
        return value if value.is_a?(Time)
        return value.to_time if value.is_a?(DateTime)

        string_value = value.to_s
        return Time.parse(string_value) if string_value.match?(/(?:Z|[+-]\d{2}:?\d{2})\z/)
        return Time.parse(string_value) if active_record_default_timezone == :local

        Time.parse("#{string_value} UTC")
      end

      def active_record_default_timezone
        if defined?(ActiveRecord) && ActiveRecord.respond_to?(:default_timezone)
          ActiveRecord.default_timezone
        else
          :utc
        end
      end
    end
  end
end
