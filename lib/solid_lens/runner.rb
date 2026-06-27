# frozen_string_literal: true

require_relative "collectors/database_collector"
require_relative "collectors/profile_collector"
require_relative "collectors/queue_config_collector"
require_relative "collectors/runtime_collector"
require_relative "collectors/table_collector"
require_relative "checks/blocked_executions_check"
require_relative "checks/claimed_executions_check"
require_relative "checks/critical_indexes_check"
require_relative "checks/database_connection_check"
require_relative "checks/database_skip_locked_check"
require_relative "checks/explain_check"
require_relative "checks/paused_queues_check"
require_relative "checks/queue_config_readiness_check"
require_relative "checks/profile_ready_backlog_check"
require_relative "checks/profile_blocked_backlog_check"
require_relative "checks/profile_claimed_executions_check"
require_relative "checks/profile_recurring_tasks_check"
require_relative "checks/profile_scheduled_backlog_check"
require_relative "checks/profile_semaphore_health_check"
require_relative "checks/profile_table_bloat_check"
require_relative "checks/pool_capacity_check"
require_relative "checks/recurring_tasks_check"
require_relative "checks/scheduler_config_check"
require_relative "checks/scheduled_jobs_check"
require_relative "checks/semaphore_health_check"
require_relative "checks/schema_readiness_check"
require_relative "checks/solid_queue_configured_check"
require_relative "checks/table_bloat_check"
require_relative "checks/wildcard_queues_check"
require_relative "checks/worker_config_check"

module SolidLens
  class Runner
    DOCTOR_CHECKS = [
      Checks::SolidQueueConfiguredCheck,
      Checks::QueueConfigReadinessCheck,
      Checks::DatabaseConnectionCheck,
      Checks::SchemaReadinessCheck,
      Checks::CriticalIndexesCheck,
      Checks::DatabaseSkipLockedCheck,
      Checks::WorkerConfigCheck,
      Checks::SchedulerConfigCheck,
      Checks::PoolCapacityCheck,
      Checks::WildcardQueuesCheck,
      Checks::PausedQueuesCheck,
      Checks::ScheduledJobsCheck,
      Checks::RecurringTasksCheck,
      Checks::SemaphoreHealthCheck,
      Checks::BlockedExecutionsCheck,
      Checks::ClaimedExecutionsCheck,
      Checks::TableBloatCheck
    ].freeze

    EXPLAIN_CHECKS = (DOCTOR_CHECKS + [Checks::ExplainCheck]).freeze
    PROFILE_CHECKS = (
      DOCTOR_CHECKS + [
        Checks::ProfileReadyBacklogCheck,
        Checks::ProfileScheduledBacklogCheck,
        Checks::ProfileRecurringTasksCheck,
        Checks::ProfileBlockedBacklogCheck,
        Checks::ProfileSemaphoreHealthCheck,
        Checks::ProfileClaimedExecutionsCheck,
        Checks::ProfileTableBloatCheck
      ]
    ).freeze

    def doctor
      run(command: "doctor", checks: DOCTOR_CHECKS)
    end

    def explain
      run(command: "explain", checks: EXPLAIN_CHECKS, explain: true)
    end

    def profile(duration: 60, sample_interval: Collectors::ProfileCollector::DEFAULT_SAMPLE_INTERVAL)
      profile_result = Collectors::ProfileCollector.new(
        evidence_collector: method(:collect_evidence),
        duration: duration,
        sample_interval: sample_interval
      ).collect
      evidence = profile_result.fetch(:evidence).merge(profile: profile_result.fetch(:profile))

      Report.new(command: "profile", evidence: evidence, findings: findings_for(evidence, PROFILE_CHECKS))
    end

    private

    def run(command:, checks:, explain: false)
      evidence = collect_evidence(explain: explain)
      Report.new(command: command, evidence: evidence, findings: findings_for(evidence, checks))
    end

    def collect_evidence(explain: false)
      database = Collectors::DatabaseCollector.new.collect
      queue_config = Collectors::QueueConfigCollector.new.collect

      {
        runtime: Collectors::RuntimeCollector.new.collect,
        queue_config: queue_config,
        database: database.fetch(:evidence),
        tables: Collectors::TableCollector.new(
          connection: database[:connection],
          queue_config: queue_config,
          database: database.fetch(:evidence),
          explain: explain
        ).collect
      }
    end

    def findings_for(evidence, checks)
      checks.flat_map { |check| check.new(evidence).call }.sort_by do |finding|
        Finding::SEVERITIES.index(finding.severity)
      end
    end
  end
end
