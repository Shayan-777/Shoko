# frozen_string_literal: true

module Shoko
  module Core
    module Services
      # Bridge that adapts the ConfigReader port to a legacy .get(path) interface.
      # Used by pagination and navigation services that need the old-style
      # state-path-based config lookups.
      class ConfigBridge
        def initialize(config_reader)
          @config_reader = config_reader
        end

        def get(path)
          case path
          when %i[config kitty_images]
            @config_reader.kitty_images
          when %i[config view_mode]
            @config_reader.view_mode
          when %i[config line_spacing]
            @config_reader.line_spacing
          end
        end
      end
    end
  end
end
