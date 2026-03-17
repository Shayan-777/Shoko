# frozen_string_literal: true

require_relative '../../../core/models/session/terminal_size'
require_relative '../../../core/models/session/display_capabilities_snapshot'
require_relative '../../../core/ports/outbound/reader_runtime_context'

module Shoko
  module Adapters
    module Runtime
      module SessionState
        # Adapter-backed runtime context that exposes live terminal dimensions and
        # derived display capabilities for reader flows.
        class ReaderRuntimeContextAdapter
          include Shoko::Core::Ports::Outbound::ReaderRuntimeContext

          KittyCapabilityConfig = Struct.new(:kitty_images, keyword_init: true)

          def initialize(terminal_session:, display_capabilities:, app_config_store:, reader_session_store:)
            @terminal_session = terminal_session
            @display_capabilities = display_capabilities
            @app_config_store = app_config_store
            @reader_session_store = reader_session_store
          end

          def terminal_size
            height, width = @terminal_session.size
            width = width.to_i
            height = height.to_i
            width = 80 if width <= 0
            height = 24 if height <= 0
            Shoko::Core::Models::Session::TerminalSize.build(width: width, height: height)
          end

          def display_capabilities
            config = @app_config_store.load
            view = KittyCapabilityConfig.new(kitty_images: config.kitty_images)
            enabled = @display_capabilities.kitty_images_enabled?(view)
            Shoko::Core::Models::Session::DisplayCapabilitiesSnapshot.build(
              kitty_images_enabled: enabled
            )
          end

          def terminal_width
            terminal_size.width
          end

          def terminal_height
            terminal_size.height
          end

          def loading_message
            @reader_session_store.load.loading_message
          end

          def loading_progress
            @reader_session_store.load.loading_progress
          end

          def terminal_size_changed?(width, height)
            snapshot = @reader_session_store.load
            width.to_i != snapshot.last_width.to_i || height.to_i != snapshot.last_height.to_i
          end
        end
      end
    end
  end
end
