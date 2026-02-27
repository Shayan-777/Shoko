# frozen_string_literal: true

require_relative '../components/surface'
require_relative '../components/screens/loading_overlay_component'

module Shoko
  module Adapters
    module Ui
      module Rendering
        # Coordinates frame lifecycle and provides a consistent surface + bounds
        # for rendering. Centralizes start_frame/end_frame and terminal size updates.
        class FrameCoordinator
          def initialize(terminal_service:, state_writer:, ui_state_reader:)
            @terminal_service = terminal_service
            @state_writer = state_writer
            @ui_state_reader = ui_state_reader
          end

          # Yields a prepared [surface, bounds, width, height] within a started frame.
          # Ensures end_frame is called, even on errors.
          def with_frame
            height, width = @terminal_service.size
            @terminal_service.start_frame(width: width, height: height)
            @state_writer.update_terminal_size(width, height)
            surface = build_surface
            bounds = Shoko::Adapters::Ui::Components::Rect.new(x: 1, y: 1, width: width, height: height)
            yield(surface, bounds, width, height)
          ensure
            @terminal_service.end_frame
          end

          # Renders the loading overlay component in a standalone frame.
          def render_loading_overlay
            height, width = @terminal_service.size
            @terminal_service.start_frame(width: width, height: height)
            surface = build_surface
            bounds = Shoko::Adapters::Ui::Components::Rect.new(x: 1, y: 1, width: width, height: height)
            overlay = Shoko::Adapters::Ui::Components::Screens::LoadingOverlayComponent.new(
              ui_state_reader: @ui_state_reader
            )
            overlay.render(surface, bounds)
          ensure
            @terminal_service.end_frame
          end

          private

          def build_surface
            Shoko::Adapters::Ui::Components::Surface.new(@terminal_service.output)
          end
        end
      end
    end
  end
end
