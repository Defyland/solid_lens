# frozen_string_literal: true

require "solid_lens"

namespace :solid_lens do
  desc "Diagnose Solid Queue configuration and database health"
  task doctor: :environment do
    SolidLens::Tasks.run("doctor")
  end

  desc "Profile Solid Queue table movement over DURATION seconds"
  task profile: :environment do
    SolidLens::Tasks.run("profile")
  end

  desc "Run diagnostic checks plus EXPLAIN on critical Solid Queue polling queries"
  task explain: :environment do
    SolidLens::Tasks.run("explain")
  end
end

module SolidLens
  module Tasks
    module_function

    def run(command)
      status = CLI.new(task_argv(command, task_options)).call
      exit(status) unless status.zero?
    end

    def task_options
      {
        duration: Integer(ENV.fetch("DURATION", env_or_argv("duration", CLI::DEFAULT_DURATION.to_s))),
        sample_interval: Float(ENV.fetch("SAMPLE_INTERVAL", env_or_argv("sample-interval", CLI::DEFAULT_SAMPLE_INTERVAL.to_s))),
        format: ENV.fetch("FORMAT", env_or_argv("format", CLI::DEFAULT_FORMAT)),
        output: ENV["OUTPUT"] || env_or_argv("output", nil),
        fail_on_high: ENV["FAIL_ON_HIGH"] == "1" || ARGV.include?("--fail-on-high")
      }
    end

    def task_argv(command, options)
      CLI.build_argv(
        command: command,
        format: options.fetch(:format),
        output: options[:output],
        fail_on_high: options[:fail_on_high],
        duration: options.fetch(:duration),
        sample_interval: options.fetch(:sample_interval)
      )
    end

    def env_or_argv(name, default)
      prefix = "--#{name}="
      match = ARGV.find { |arg| arg.start_with?(prefix) }
      match ? match.delete_prefix(prefix) : default
    end
  end
end
