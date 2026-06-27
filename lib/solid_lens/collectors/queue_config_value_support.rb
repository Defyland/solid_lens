# frozen_string_literal: true

module SolidLens
  module Collectors
    module QueueConfigValueSupport
      private

      def normalize_list(value, defaults)
        list = case value
        when Array then value
        when nil then [defaults]
        else [value]
        end

        list.map do |item|
          merge_defaults(defaults, stringify_keys(item || {}))
        end
      end

      def merge_defaults(defaults, overrides)
        defaults.merge(overrides) do |_key, default_value, override_value|
          if default_value.is_a?(Hash) && override_value.is_a?(Hash)
            merge_defaults(default_value, override_value)
          elsif override_value.nil?
            default_value
          else
            override_value
          end
        end
      end

      def stringify_keys(value)
        case value
        when Hash
          value.to_h { |key, child| [key.to_s, stringify_keys(child)] }
        when Array
          value.map { |child| stringify_keys(child) }
        else
          value
        end
      end
    end
  end
end
