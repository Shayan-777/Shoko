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

          ConfigView = Struct.new(:kitty_images, keyword_init: true)

          def initialize(terminal_session:, display_capabilities:, app_config_store:)
            @terminal_session = terminal_session
            @display_capabilities = display_capabilities
            @app_config_store = app_config_store
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
            view = ConfigView.new(kitty_images: config.kitty_images)
            enabled = @display_capabilities.kitty_images_enabled?(view)
            Shoko::Core::Models::Session::DisplayCapabilitiesSnapshot.build(
              kitty_images_enabled: enabled
            )
          end
        end
      end
    end
  end
end
