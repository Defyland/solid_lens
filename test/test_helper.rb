# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "minitest/autorun"
require "solid_lens"

Dir[File.expand_path("support/**/*.rb", __dir__)].sort.each { |file| require file }
