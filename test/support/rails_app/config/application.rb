# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"
ENV["RACK_ENV"] ||= ENV["RAILS_ENV"]

require "bundler/setup"
require "logger"
require "rails"
require "active_job/railtie"
require "active_record/railtie"
require "solid_queue"
require "solid_lens/railtie"

module SolidLensIntegrationTestApp
  class Application < Rails::Application
    config.root = File.expand_path("..", __dir__)
    config.eager_load = false
    config.logger = Logger.new(nil)
    config.secret_key_base = "solid-lens-integration-secret"
    config.active_job.queue_adapter = :solid_queue
    config.solid_queue.connects_to = {database: {writing: :primary}}
    config.load_defaults 8.1 if config.respond_to?(:load_defaults)
  end
end
