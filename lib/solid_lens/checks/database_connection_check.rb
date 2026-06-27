# frozen_string_literal: true

require_relative "base_check"

module SolidLens
  module Checks
    class DatabaseConnectionCheck < BaseCheck
      def call
        return [] unless database[:connected] == false

        [
          finding(
            id: "solid_queue.database.unavailable",
            severity: :high,
            title: "Queue database connection is unavailable",
            evidence: {
              error: database[:error],
              solid_queue_connects_to: runtime[:solid_queue_connects_to],
              rails_env: runtime[:rails_env]
            },
            recommendation: "Boot the Rails environment, verify config.solid_queue.connects_to and the queue database entry in config/database.yml, then rerun SolidLens."
          )
        ]
      end
    end
  end
end
