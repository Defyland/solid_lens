# frozen_string_literal: true

require "json"

module SolidLens
  module Reporters
    class JsonReporter
      def initialize(report)
        @report = report
      end

      def render
        JSON.pretty_generate(@report.to_h)
      end
    end
  end
end
