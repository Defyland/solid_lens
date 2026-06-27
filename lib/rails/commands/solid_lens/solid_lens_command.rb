# frozen_string_literal: true

require "solid_lens"

module Rails
  module Command
    class SolidLensCommand < Base
      namespace "solid_lens"

      class_option :format, type: :string, default: SolidLens::CLI::DEFAULT_FORMAT, desc: "markdown or json"
      class_option :output, type: :string, desc: "write report to path"
      class_option :fail_on_high, type: :boolean, default: false, desc: "exit non-zero when high or critical findings exist"

      desc "doctor", "Diagnose Solid Queue configuration and database health"
      def doctor
        invoke_cli("doctor")
      end

      desc "profile", "Profile Solid Queue table movement over time"
      method_option :duration, type: :numeric, default: SolidLens::CLI::DEFAULT_DURATION, desc: "profile duration in seconds"
      method_option :sample_interval, type: :numeric, default: SolidLens::CLI::DEFAULT_SAMPLE_INTERVAL, desc: "profile sampling interval in seconds"
      def profile
        invoke_cli(
          "profile",
          duration: options.fetch(:duration),
          sample_interval: options.fetch(:sample_interval)
        )
      end

      desc "explain", "Run diagnostic checks plus EXPLAIN on critical Solid Queue polling queries"
      def explain
        invoke_cli("explain")
      end

      private

      def invoke_cli(command, duration: nil, sample_interval: nil)
        args = SolidLens::CLI.build_argv(
          command: command,
          app_root: Rails::Command.root,
          format: options.fetch(:format),
          output: options[:output],
          fail_on_high: options[:fail_on_high],
          duration: duration,
          sample_interval: sample_interval
        )

        exit SolidLens::CLI.new(args).call
      end
    end
  end
end
