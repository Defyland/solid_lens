# frozen_string_literal: true

module SolidLens
  module Checks
    module ConcurrencyMaintenanceSupport
      DISPATCHER_DEFAULTS = {
        "concurrency_maintenance" => true,
        "concurrency_maintenance_interval" => 600
      }.freeze

      private

      def dispatchers
        Array(queue_config[:dispatchers])
      end

      def enabled_dispatchers
        @enabled_dispatchers ||= dispatchers.each_with_index.filter_map do |dispatcher, index|
          next unless maintenance_path_enabled?(dispatcher)

          {
            "dispatcher_index" => index,
            "polling_interval" => dispatcher.fetch("polling_interval", nil),
            "concurrency_maintenance_interval" => concurrency_maintenance_interval(dispatcher)
          }
        end
      end

      def fastest_concurrency_maintenance_interval
        enabled_dispatchers.map { |dispatcher| dispatcher.fetch("concurrency_maintenance_interval").to_f }.min || 0.0
      end

      def concurrency_maintenance_enabled?(dispatcher)
        value = dispatcher.fetch("concurrency_maintenance", DISPATCHER_DEFAULTS.fetch("concurrency_maintenance"))

        case value
        when false, 0 then false
        else !value.to_s.casecmp("false").zero?
        end
      end

      def maintenance_path_enabled?(dispatcher)
        return false unless concurrency_maintenance_enabled?(dispatcher)
        return false unless polling_interval(dispatcher).positive?
        return false unless concurrency_maintenance_interval(dispatcher).positive?

        true
      end

      def polling_interval(dispatcher)
        dispatcher.fetch("polling_interval", 0).to_f
      end

      def concurrency_maintenance_interval(dispatcher)
        dispatcher.fetch(
          "concurrency_maintenance_interval",
          DISPATCHER_DEFAULTS.fetch("concurrency_maintenance_interval")
        ).to_f
      end
    end
  end
end
