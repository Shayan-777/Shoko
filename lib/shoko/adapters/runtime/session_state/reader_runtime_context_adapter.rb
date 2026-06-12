# frozen_string_literal: true

require_relative '../../../application/ports/outbound/state/terminal_size'
require_relative '../../../application/ports/outbound/state/display_capabilities_snapshot'
require_relative '../../../application/ports/outbound/reader_runtime_context'
require_relative '../../../application/ports/outbound/reader_view_state_store'
require_relative '../../../application/ports/outbound/reader_pagination_store'

module Shoko
  module Adapters
    module Runtime
      module SessionState
        # Adapter-backed runtime context that exposes live terminal dimensions and
        # derived display capabilities for reader flows.
        class ReaderRuntimeContextAdapter
          include Shoko::Application::Ports::Outbound::ReaderRuntimeContext

          KittyCapabilityConfig = Struct.new(:kitty_images)

          def initialize(terminal_session:, display_capabilities:, app_config_store:, reader_view_state_store: nil,
                         reader_pagination_store: nil, reader_session_store: nil)
            @terminal_session = terminal_session
            @display_capabilities = display_capabilities
            @app_config_store = app_config_store
            @reader_view_state_store = reader_view_state_store || reader_session_store
            @reader_pagination_store = reader_pagination_store || reader_session_store
          end

          def terminal_size
            height, width = @terminal_session.size
            width = width.to_i
            height = height.to_i
            width = 80 if width <= 0
            height = 24 if height <= 0
            Shoko::Application::Ports::Outbound::State::TerminalSize.build(width: width, height: height)
          end

          def display_capabilities
            config = @app_config_store.load
            view = KittyCapabilityConfig.new(config.kitty_images)
            enabled = @display_capabilities.kitty_images_enabled?(view)
            Shoko::Application::Ports::Outbound::State::DisplayCapabilitiesSnapshot.build(kitty_images_enabled: enabled)
          end

          def terminal_width
            terminal_size.width
          end

          def terminal_height
            terminal_size.height
          end

          def loading_message
            @reader_view_state_store.loading_message
          end

          def loading_progress
            @reader_view_state_store.loading_progress
          end

          def terminal_size_changed?(width, height)
            width.to_i != @reader_pagination_store.last_width.to_i ||
              height.to_i != @reader_pagination_store.last_height.to_i
          end
        end
      end
    end
  end
end
