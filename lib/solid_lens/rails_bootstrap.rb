# frozen_string_literal: true

require "pathname"

module SolidLens
  class RailsBootstrap
    class Error < StandardError; end

    def initialize(app_root: nil, rails_env: nil, boot_rails: true)
      @app_root = app_root
      @rails_env = rails_env
      @boot_rails = boot_rails
    end

    def boot!
      return false unless boot_rails
      return false if rails_application_loaded?

      root = resolved_app_root
      return false unless root

      apply_environment!
      require root.join("config/environment").to_s
      true
    rescue LoadError, StandardError => error
      raise Error, "failed to boot Rails app at #{root || @app_root || Dir.pwd}: #{error.class}: #{error.message}"
    end

    private

    attr_reader :app_root, :rails_env, :boot_rails

    def resolved_app_root
      candidate = app_root ? Pathname.new(app_root).expand_path : discover_app_root
      return unless candidate
      return unless candidate.join("config/application.rb").exist? && candidate.join("config/environment.rb").exist?

      candidate
    end

    def discover_app_root
      Pathname.new(Dir.pwd).expand_path.ascend do |path|
        return path if path.join("config/application.rb").exist? && path.join("config/environment.rb").exist?
      end

      nil
    end

    def apply_environment!
      return unless rails_env

      ENV["RAILS_ENV"] = rails_env
      ENV["RACK_ENV"] = rails_env
    end

    def rails_application_loaded?
      defined?(Rails) && Rails.respond_to?(:application) && Rails.application
    rescue
      false
    end
  end
end
