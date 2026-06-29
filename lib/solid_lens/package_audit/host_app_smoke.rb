# frozen_string_literal: true

require "json"

module SolidLens
  module PackageAudit
    module HostAppSmoke
      module_function

      def verify!(gem_path:)
        Dir.mktmpdir("solid-lens-host-app") do |directory|
          app_root = File.join(directory, "host_app")
          gem_home = File.join(directory, "gems")
          FileUtils.mkdir_p(gem_home)

          installed_spec = PackageAudit.install_built_gem!(gem_path, gem_home)
          bundler_gem_path = unpack_built_gem_for_bundler!(app_root, gem_path, installed_spec)
          write_host_app!(app_root, bundler_gem_path)

          env = host_app_bundle_env(app_root, gem_home)
          run_bundle!(app_root, env, "install", "--local")
          verify_loaded_gem!(app_root, env, installed_spec.version, bundler_gem_path)
          prepare_queue_schema!(app_root, env)
          verify_cli_command!(directory, app_root, env)
          verify_rails_command!(app_root, env)
        end
      end

      def host_app_bundle_env(app_root, gem_home)
        env = PackageAudit.sanitized_env.merge(
          "BUNDLE_APP_CONFIG" => File.join(app_root, ".bundle"),
          "BUNDLE_GEMFILE" => File.join(app_root, "Gemfile"),
          "GEM_HOME" => gem_home,
          "GEM_PATH" => ([gem_home] + PackageAudit.base_gem_paths).uniq.join(File::PATH_SEPARATOR)
        )
        env["BUNDLE_PATH"] = PackageAudit.bundler_configured_path if PackageAudit.bundler_configured_path
        env
      end

      def write_host_app!(app_root, bundler_gem_path)
        write_file(
          app_root,
          "Gemfile",
          <<~RUBY
            source "https://rubygems.org"

            gem "activesupport", "= #{host_dependency_version("activesupport")}"
            gem "activejob", "= #{host_dependency_version("activejob")}"
            gem "activerecord", "= #{host_dependency_version("activerecord")}"
            gem "railties", "= #{host_dependency_version("railties")}"
            gem "solid_queue", "= #{host_dependency_version("solid_queue")}"
            gem "sqlite3", "= #{host_dependency_version("sqlite3")}"
            gem "solid_lens", path: #{bundler_gem_path.inspect}
          RUBY
        )

        write_file(
          app_root,
          "config/boot.rb",
          <<~RUBY
            ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)
            require "bundler/setup"
          RUBY
        )

        write_file(
          app_root,
          "config/application.rb",
          <<~RUBY
            # frozen_string_literal: true

            ENV["RAILS_ENV"] ||= "development"
            ENV["RACK_ENV"] ||= ENV["RAILS_ENV"]

            require_relative "boot"
            require "logger"
            require "rails"
            require "active_job/railtie"
            require "active_record/railtie"
            require "solid_queue"
            require "solid_lens/railtie"

            module SolidLensPackageAuditHostApp
              class Application < Rails::Application
                config.root = File.expand_path("..", __dir__)
                config.eager_load = false
                config.logger = Logger.new(nil)
                config.secret_key_base = "solid-lens-package-audit-secret"
                config.active_job.queue_adapter = :solid_queue
                config.solid_queue.connects_to = {database: {writing: :primary}}
                config.load_defaults 8.1 if config.respond_to?(:load_defaults)
              end
            end
          RUBY
        )

        write_file(
          app_root,
          "config/environment.rb",
          <<~RUBY
            require_relative "application"

            SolidLensPackageAuditHostApp::Application.initialize!
          RUBY
        )

        write_file(
          app_root,
          "config/database.yml",
          <<~YAML
            default: &default
              adapter: sqlite3
              database: #{File.join(app_root, "tmp/solid_lens_package_audit.sqlite3")}
              timeout: 5000
              pool: 5

            development:
              primary:
                <<: *default

            test:
              primary:
                <<: *default

            production:
              primary:
                <<: *default
          YAML
        )

        write_file(
          app_root,
          "config/queue.yml",
          <<~YAML
            development: &default
              dispatchers:
                - polling_interval: 1
                  batch_size: 250
                  concurrency_maintenance_interval: 600
              workers:
                - queues:
                    - default
                  threads: 4
                  processes: 2
                  polling_interval: 0.2
              scheduler:
                polling_interval: 5
                dynamic_tasks_enabled: true

            test:
              <<: *default

            production:
              <<: *default
          YAML
        )

        write_file(
          app_root,
          "config/recurring.yml",
          <<~YAML
            {}
          YAML
        )

        write_file(
          app_root,
          "bin/rails",
          <<~RUBY
            #!/usr/bin/env ruby
            # frozen_string_literal: true

            APP_PATH = File.expand_path("../config/application", __dir__)

            require_relative "../config/boot"
            require "rails/commands"
          RUBY
        )

        FileUtils.chmod("+x", File.join(app_root, "bin/rails"))
      end

      def verify_loaded_gem!(app_root, env, expected_version, expected_gem_path)
        PackageAudit.run_command!(
          env.merge(
            "EXPECTED_GEM_PATH" => File.realpath(expected_gem_path),
            "EXPECTED_GEM_VERSION" => expected_version.to_s
          ),
          bundle_command("exec", "ruby", "-e", loaded_gem_script),
          failure_message: "Bundler did not resolve solid_lens from the built gem contents.",
          chdir: app_root
        )
      end

      def prepare_queue_schema!(app_root, env)
        PackageAudit.run_command!(
          env.merge("RAILS_ENV" => "production", "RACK_ENV" => "production"),
          bundle_command("exec", "ruby", "-e", schema_load_script),
          failure_message: "Disposable Rails host app failed to load the Solid Queue schema.",
          chdir: app_root
        )
      end

      def verify_cli_command!(directory, app_root, env)
        stdout = PackageAudit.run_command!(
          env.merge("RAILS_ENV" => "production", "RACK_ENV" => "production"),
          bundle_command(
            "exec",
            "solid_lens",
            "doctor",
            "--app-root=#{app_root}",
            "--rails-env=production",
            "--format=json",
            "--fail-on-high"
          ),
          failure_message: "Disposable Rails host app failed to execute the packaged SolidLens CLI.",
          chdir: directory,
          allowed_exit_codes: [1]
        )

        payload = JSON.parse(stdout)
        return if report_payload_valid?(payload, expected_env: "production")

        raise PackageAudit::Error, "Disposable Rails host app returned unexpected JSON from the packaged SolidLens CLI."
      rescue JSON::ParserError => e
        raise PackageAudit::Error,
          "Disposable Rails host app did not emit valid JSON from the packaged SolidLens CLI: #{e.message}"
      end

      def verify_rails_command!(app_root, env)
        output_path = File.join(app_root, "tmp/reports/solid_lens.json")

        output = PackageAudit.run_command!(
          env.merge("RAILS_ENV" => "production", "RACK_ENV" => "production"),
          bundle_command(
            "exec",
            "bin/rails",
            "solid_lens:doctor",
            "--format=json",
            "--output=#{output_path}"
          ),
          failure_message: "Disposable Rails host app failed to execute the packaged Rails command surface.",
          chdir: app_root
        )

        raise PackageAudit::Error, "Packaged Rails command wrote unexpected stdout." unless output.empty?
        raise PackageAudit::Error, "Packaged Rails command did not create the requested output file." unless File.exist?(output_path)

        payload = JSON.parse(File.read(output_path))
        return if report_payload_valid?(payload, expected_env: "production")

        raise PackageAudit::Error, "Disposable Rails host app returned unexpected JSON from the packaged Rails command surface."
      rescue JSON::ParserError => e
        raise PackageAudit::Error,
          "Disposable Rails host app did not emit valid JSON from the packaged Rails command surface: #{e.message}"
      end

      def report_payload_valid?(payload, expected_env:)
        payload.fetch("command") == "doctor" &&
          payload.dig("evidence", "runtime", "rails_env") == expected_env &&
          payload.dig("evidence", "database", "connected") == true &&
          payload.fetch("findings").any? { |finding| finding.fetch("id") == "solid_queue.pool.undersized" }
      end

      def host_dependency_version(name)
        spec = Gem.loaded_specs[name] || Gem::Specification.find_by_name(name)
        spec.version.to_s
      end

      def run_bundle!(app_root, env, *arguments)
        PackageAudit.run_command!(
          env,
          bundle_command(*arguments),
          failure_message: "Disposable Rails host app failed to run `bundle #{arguments.join(" ")}`.",
          chdir: app_root
        )
      end

      def bundle_command(*arguments)
        [Gem.ruby, Gem.bin_path("bundler", "bundle"), *arguments]
      end

      def write_file(app_root, relative_path, contents)
        path = File.join(app_root, relative_path)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, contents)
      end

      def unpack_built_gem_for_bundler!(app_root, gem_path, installed_spec)
        bundler_gem_path = File.join(app_root, "vendor/gems/solid_lens")
        FileUtils.rm_rf(bundler_gem_path)
        FileUtils.mkdir_p(bundler_gem_path)
        Gem::Package.new(gem_path).extract_files(bundler_gem_path)
        File.write(File.join(bundler_gem_path, "solid_lens.gemspec"), installed_spec.to_ruby)
        bundler_gem_path
      end

      def loaded_gem_script
        <<~RUBY
          require "solid_lens"
          spec = Gem.loaded_specs.fetch("solid_lens")
          real_path = File.realpath(spec.full_gem_path)
          abort("loaded gem version mismatch") unless spec.version.to_s == ENV.fetch("EXPECTED_GEM_VERSION")
          abort("loaded gem path does not match unpacked built gem") unless real_path == ENV.fetch("EXPECTED_GEM_PATH")
        RUBY
      end

      def schema_load_script
        <<~RUBY
          require "./config/environment"

          begin
            schema_path = Gem::Specification.find_by_name("solid_queue").full_gem_path
            verbose_was = ActiveRecord::Migration.verbose
            ActiveRecord::Migration.verbose = false
            load File.join(schema_path, "lib/generators/solid_queue/install/templates/db/queue_schema.rb")
          ensure
            ActiveRecord::Migration.verbose = verbose_was unless verbose_was.nil?
          end
        RUBY
      end
    end
  end
end
