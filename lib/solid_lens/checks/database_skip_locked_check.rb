# frozen_string_literal: true

require_relative "base_check"

module SolidLens
  module Checks
    class DatabaseSkipLockedCheck < BaseCheck
      def call
        return [] if database[:skip_locked_supported] != false

        severity = (queue_config.fetch(:worker_thread_capacity, 0).to_i > 1) ? :high : :medium
        [
          finding(
            id: "solid_queue.database.skip_locked_unsupported",
            severity: severity,
            title: "Queue database does not support SKIP LOCKED",
            evidence: {
              adapter_name: database[:adapter_name],
              database_version: database[:database_version],
              skip_locked_supported: database[:skip_locked_supported]
            },
            recommendation: "Use MySQL 8+, MariaDB 10.6+, or PostgreSQL 9.5+ for high-throughput Solid Queue workers, or keep concurrency low on SQLite/older databases."
          )
        ]
      end
    end
  end
end
