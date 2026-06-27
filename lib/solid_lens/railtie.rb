# frozen_string_literal: true

require "rails/railtie"

module SolidLens
  class Railtie < Rails::Railtie
    rake_tasks do
      load "tasks/solid_lens.rake"
    end
  end
end
