# frozen_string_literal: true

require "fileutils"
require "optparse"
require_relative "reporters/json_reporter"
require_relative "reporters/markdown_reporter"

module SolidLens
  class CLI
    DEFAULT_FORMAT = "markdown"
    DEFAULT_DURATION = 60
    DEFAULT_SAMPLE_INTERVAL = Collectors::ProfileCollector::DEFAULT_SAMPLE_INTERVAL

    def self.build_argv(command:, format: DEFAULT_FORMAT, output: nil, fail_on_high: false, duration: DEFAULT_DURATION, sample_interval: DEFAULT_SAMPLE_INTERVAL, app_root: nil, rails_env: nil, boot_rails: nil)
      argv = [command.to_s]
      argv << "--app-root=#{app_root}" if app_root
      argv << "--rails-env=#{rails_env}" if rails_env
      argv << "--boot-rails" if boot_rails == true
      argv << "--no-boot-rails" if boot_rails == false
      argv << "--format=#{format}"
      argv << "--output=#{output}" if output
      argv << "--fail-on-high" if fail_on_high

      if command.to_s == "profile"
        argv << "--duration=#{duration}"
        argv << "--sample-interval=#{sample_interval}"
      end

      argv
    end

    def initialize(argv, stdout: $stdout, stderr: $stderr)
      @argv = argv.dup
      @stdout = stdout
      @stderr = stderr
    end

    def call
      command = @argv.shift || "doctor"
      options = parse_options(@argv)
      bootstrap(options)
      report = run(command, options)
      rendered = render(report, options.fetch(:format))

      if options[:output]
        write_output(options[:output], rendered)
      else
        @stdout.puts rendered
      end

      options[:fail_on_high] ? report.exit_status : 0
    rescue OptionParser::ParseError, ArgumentError, RailsBootstrap::Error, SystemCallError => error
      @stderr.puts "solid_lens: #{error.message}"
      64
    end

    private

    def parse_options(argv)
      options = {format: DEFAULT_FORMAT, duration: DEFAULT_DURATION, sample_interval: DEFAULT_SAMPLE_INTERVAL, fail_on_high: false}

      OptionParser.new do |parser|
        parser.on("--app-root=PATH", "boot the Rails app at PATH before running diagnostics") { |path| options[:app_root] = path }
        parser.on("--rails-env=ENV", "set RAILS_ENV/RACK_ENV before booting Rails") { |env| options[:rails_env] = env }
        parser.on("--[no-]boot-rails", "auto-boot Rails when a Rails app is detected") { |value| options[:boot_rails] = value }
        parser.on("--format=FORMAT", "markdown or json") { |format| options[:format] = format }
        parser.on("--output=PATH", "write report to path") { |path| options[:output] = path }
        parser.on("--duration=SECONDS", Integer, "profile duration") { |seconds| options[:duration] = seconds }
        parser.on("--sample-interval=SECONDS", Float, "profile sampling interval") { |seconds| options[:sample_interval] = seconds }
        parser.on("--fail-on-high", "exit non-zero when high/critical findings exist") { options[:fail_on_high] = true }
      end.parse!(argv)

      options
    end

    def run(command, options)
      case command
      when "doctor"
        Runner.new.doctor
      when "profile"
        Runner.new.profile(duration: options.fetch(:duration), sample_interval: options.fetch(:sample_interval))
      when "explain"
        Runner.new.explain
      else
        raise ArgumentError, "unknown command #{command.inspect}; expected doctor, profile, or explain"
      end
    end

    def bootstrap(options)
      RailsBootstrap.new(
        app_root: options[:app_root],
        rails_env: options[:rails_env],
        boot_rails: options.fetch(:boot_rails, true)
      ).boot!
    end

    def render(report, format)
      case format
      when "json"
        Reporters::JsonReporter.new(report).render
      when "markdown", "md"
        Reporters::MarkdownReporter.new(report).render
      else
        raise ArgumentError, "unknown format #{format.inspect}; expected markdown or json"
      end
    end

    def write_output(path, rendered)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, rendered)
    end
  end
end
