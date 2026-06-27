# frozen_string_literal: true

require "time"

require_relative "solid_lens/version"
require_relative "solid_lens/finding"
require_relative "solid_lens/report"
require_relative "solid_lens/rails_bootstrap"
require_relative "solid_lens/runner"
require_relative "solid_lens/cli"

require_relative "solid_lens/railtie" if defined?(Rails::Railtie)
