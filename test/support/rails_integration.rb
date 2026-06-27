# frozen_string_literal: true

require "erb"
require "fileutils"
require "json"
require "logger"
require "open3"
require "pathname"
require "rake"
require "stringio"
require "yaml"

module SolidLens
  module TestSupport
    module RailsIntegration
      module_function

      APP_ROOT = Pathname.new(File.expand_path("rails_app", __dir__))
      DB_PATH = APP_ROOT.join("tmp/solid_lens_integration.sqlite3")
      REPO_ROOT = Pathname.new(File.expand_path("../..", __dir__))

      def boot!
        if defined?(Rails) && Rails.respond_to?(:application) && Rails.application
          load_rake_tasks unless Rake::Task.task_defined?("solid_lens:doctor")
          return
        end

        ENV["RAILS_ENV"] = "test"
        FileUtils.mkdir_p(DB_PATH.dirname)
        FileUtils.rm_f(DB_PATH)
        require APP_ROOT.join("config/environment").to_s

        ActiveRecord::Base.establish_connection(database_configuration)
        ActiveJob::Base.queue_adapter = :solid_queue
        load_solid_queue_schema
        load_rake_tasks
      end

      def reset_database!
        boot!
        reset_sqlite_database! if sqlite_fixture_database?
        load_solid_queue_schema
      end

      def with_env(changes)
        original = changes.to_h { |key, _value| [key, ENV[key]] }
        changes.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
        yield
      ensure
        original.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
      end

      def capture_stdout
        original_stdout = $stdout
        captured = StringIO.new
        $stdout = captured
        yield
        captured.string
      ensure
        $stdout = original_stdout
      end

      def capture_cli(*args, chdir: APP_ROOT, env: {})
        command = ["bundle", "exec", "ruby", "-I#{REPO_ROOT.join("lib")}", REPO_ROOT.join("exe/solid_lens").to_s, *args]
        Open3.capture3(bundle_env.merge(env), *command, chdir: chdir.to_s)
      end

      def capture_bin_rails(*args, chdir: APP_ROOT, env: {})
        command = ["bundle", "exec", "bin/rails", *args]
        Open3.capture3(bundle_env.merge(env), *command, chdir: chdir.to_s)
      end

      def capture_rails_script(script, chdir: APP_ROOT, env: {})
        command = ["bundle", "exec", "ruby", "-I#{REPO_ROOT.join("lib")}", "-e", script]
        Open3.capture3(bundle_env.merge(env), *command, chdir: chdir.to_s)
      end

      def prepare_schema_via_subprocess(env: {})
        script = <<~RUBY
          require #{APP_ROOT.join("config/environment").to_s.inspect}
          begin
            schema_path = Gem::Specification.find_by_name("solid_queue").full_gem_path
            verbose_was = ActiveRecord::Migration.verbose
            ActiveRecord::Migration.verbose = false
            load File.join(schema_path, "lib/generators/solid_queue/install/templates/db/queue_schema.rb")
          ensure
            ActiveRecord::Migration.verbose = verbose_was unless verbose_was.nil?
          end
        RUBY

        capture_rails_script(script, env: env)
      end

      def load_solid_queue_schema
        schema_path = Gem::Specification.find_by_name("solid_queue").full_gem_path
        verbose_was = ActiveRecord::Migration.verbose
        ActiveRecord::Migration.verbose = false
        load File.join(schema_path, "lib/generators/solid_queue/install/templates/db/queue_schema.rb")
      ensure
        ActiveRecord::Migration.verbose = verbose_was
      end

      def load_rake_tasks
        Rake.application = Rake::Application.new
        Rails.application.load_tasks
      end

      def database_configuration
        raw = ERB.new(APP_ROOT.join("config/database.yml").read).result
        YAML.safe_load(raw, aliases: true).fetch("test").fetch("primary")
      end

      def bundle_env
        {"BUNDLE_GEMFILE" => REPO_ROOT.join("Gemfile").to_s}
      end

      def reset_sqlite_database!
        ActiveRecord::Base.connection_handler.clear_all_connections!
        FileUtils.mkdir_p(DB_PATH.dirname)
        FileUtils.rm_f(DB_PATH)
        ActiveRecord::Base.establish_connection(database_configuration)
        SolidQueue::Record.establish_connection(database_configuration)
      end

      def sqlite_fixture_database?
        configuration = database_configuration
        configuration.fetch("adapter", "").to_s.casecmp("sqlite3").zero? &&
          configuration.fetch("database", "").to_s == DB_PATH.to_s
      end
    end
  end
end
