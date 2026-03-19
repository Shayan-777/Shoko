# frozen_string_literal: true

require_relative 'runtime_fields'
require_relative 'defaults'

module Shoko
  module Core
    module Models
      module Session
        # Canonical session runtime-state assembly.
        module Schema
          module_function

          def initial_runtime_state(terminal_capabilities:)
            {
              reader: reader_state_defaults,
              menu: menu_state_defaults,
              config: config_state_defaults(terminal_capabilities: terminal_capabilities),
              ui: ui_state_defaults,
            }
          end

          def reader_state_defaults
            READER_DEFAULTS.except(*UI_BACKED_READER_FIELDS)
          end

          def menu_state_defaults
            MENU_DEFAULTS.dup
          end

          def config_state_defaults(terminal_capabilities:)
            CONFIG_DEFAULTS.merge(
              kitty_images: terminal_capabilities.kitty_graphics_supported?
            )
          end

          def ui_state_defaults
            UI_DEFAULTS.dup
          end
        end
      end
    end
  end
end
