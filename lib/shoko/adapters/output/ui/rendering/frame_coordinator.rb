# frozen_string_literal: true

require_relative '../components/screens/loading_overlay_component'

module Shoko
  module Adapters::Output::Ui
    module Rendering
      # Coordinates frame lifecycle and provides a consistent surface + bounds
      # for rendering. Centralizes start_frame/end_frame and terminal size updates.
      class FrameCoordinator
        def initialize(dependencies)
          @dependencies = dependencies
          @terminal_service = @dependencies.resolve(:terminal_service)
          @state = @dependencies.resolve(:global_state)
        end

        # Yields a prepared [surface, bounds, width, height] within a started frame.
        # Ensures end_frame is called, even on errors.
        def with_frame
          height, width = @terminal_service.size
          @terminal_service.start_frame(width: width, height: height)
          @state.update_terminal_size(width, height)
          surface = @terminal_service.create_surface
          bounds = Shoko::Adapters::Output::Ui::Components::Rect.new(x: 1, y: 1, width: width, height: height)
          yield(surface, bounds, width, height)
        ensure
          @terminal_service.end_frame
        end

        # Renders the loading overlay component in a standalone frame.
        def render_loading_overlay
          height, width = @terminal_service.size
          @terminal_service.start_frame(width: width, height: height)
          surface = @terminal_service.create_surface
          bounds = Shoko::Adapters::Output::Ui::Components::Rect.new(x: 1, y: 1, width: width, height: height)
          overlay = Shoko::Adapters::Output::Ui::Components::Screens::LoadingOverlayComponent.new(@dependencies)
          overlay.render(surface, bounds)
        ensure
          @terminal_service.end_frame
        end
      end
    end
  end
end
