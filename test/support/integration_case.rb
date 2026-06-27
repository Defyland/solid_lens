# frozen_string_literal: true

require "tmpdir"

class ConcurrencyLimitedJob
  class << self
    def concurrency_duration
      5.minutes
    end

    def concurrency_limit
      1
    end

    def concurrency_on_conflict
      :block
    end
  end
end

class SolidLensIntegrationCase < Minitest::Test
  def setup
    SolidLens::TestSupport::RailsIntegration.boot!
    SolidLens::TestSupport::RailsIntegration.reset_database!
    SolidQueue.process_alive_threshold = 5.minutes
  end

  private

  def create_ready_execution(queue_name:, created_at:)
    job = SolidQueue::Job.create!(
      queue_name: queue_name,
      class_name: "TestJob",
      arguments: "[]"
    )

    job.update_columns(created_at: created_at, updated_at: created_at)
    job.ready_execution.update_columns(created_at: created_at)
  end

  def create_scheduled_execution(queue_name:, scheduled_at:)
    job = SolidQueue::Job.create!(
      queue_name: queue_name,
      class_name: "TestJob",
      arguments: "[]",
      scheduled_at: 1.hour.from_now
    )

    job.update_columns(created_at: scheduled_at, updated_at: scheduled_at, scheduled_at: scheduled_at)
    job.scheduled_execution.update_columns(created_at: scheduled_at, scheduled_at: scheduled_at)
  end

  def create_blocked_execution(queue_name:, concurrency_key:, created_at:, expires_at:)
    job = SolidQueue::Job.create!(
      queue_name: queue_name,
      class_name: "ConcurrencyLimitedJob",
      arguments: "[]",
      concurrency_key: concurrency_key
    )

    job.update_columns(created_at: created_at, updated_at: created_at)
    job.ready_execution&.destroy!

    blocked_execution = SolidQueue::BlockedExecution.create!(job: job)
    blocked_execution.update_columns(created_at: created_at, expires_at: expires_at)
  end

  def create_semaphore(key:, value:, expires_at:, created_at:)
    semaphore = SolidQueue::Semaphore.create!(
      key: key,
      value: value,
      expires_at: expires_at
    )

    semaphore.update_columns(created_at: created_at, updated_at: created_at, expires_at: expires_at)
  end

  def create_stale_claimed_execution(last_heartbeat_at:)
    @stale_claim_sequence = @stale_claim_sequence.to_i + 1

    process = SolidQueue::Process.create!(
      kind: "Worker",
      last_heartbeat_at: last_heartbeat_at,
      pid: 10_000 + @stale_claim_sequence,
      hostname: "localhost",
      metadata: "{}",
      name: "worker-#{@stale_claim_sequence}"
    )
    job = SolidQueue::Job.create!(queue_name: "default", class_name: "TestJob", arguments: "[]")
    job.ready_execution&.destroy!
    SolidQueue::ClaimedExecution.create!(job_id: job.id, process_id: process.id)
  end

  def create_dynamic_recurring_task(key:, schedule:, created_at:)
    task = SolidQueue::RecurringTask.create!(
      key: key,
      schedule: schedule,
      command: "Maintenance.run",
      static: false
    )

    task.update_columns(created_at: created_at, updated_at: created_at)
  end

  def create_static_recurring_task(key:, schedule:, created_at:)
    task = SolidQueue::RecurringTask.create!(
      key: key,
      schedule: schedule,
      command: "Maintenance.run",
      static: true
    )

    task.update_columns(created_at: created_at, updated_at: created_at)
  end

  def capture_rake_task(command, env: {})
    SolidLens::TestSupport::RailsIntegration.capture_rails_script(<<~RUBY, env: env)
      require "rake"
      require #{SolidLens::TestSupport::RailsIntegration::APP_ROOT.join("config/environment").to_s.inspect}
      Rake.application = Rake::Application.new
      Rails.application.load_tasks
      Rake::Task[#{("solid_lens:" + command).inspect}].invoke
    RUBY
  end
end
