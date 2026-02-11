# frozen_string_literal: true

require_relative '../../../core/ports/rendering_factory'
require_relative 'rendering/frame_coordinator'
require_relative 'rendering/render_pipeline'
require_relative 'rendering/reader_render_coordinator'

module Shoko
  module Adapters::Output::Ui
    # Adapter implementing the RenderingFactory port.
    # Creates FrameCoordinator, RenderPipeline, and ReaderRenderCoordinator instances.
    class RenderingFactoryAdapter
      include Core::Ports::RenderingFactory

      def create_frame_coordinator(terminal_service:, global_state:, ui_state_reader:)
        Rendering::FrameCoordinator.new(
          terminal_service: terminal_service,
          global_state: global_state,
          ui_state_reader: ui_state_reader
        )
      end

      def create_render_pipeline(global_state:, reader_state_reader:, logger: nil)
        Rendering::RenderPipeline.new(
          global_state: global_state,
          reader_state_reader: reader_state_reader,
          logger: logger
        )
      end

      def create_reader_render_coordinator(reader_dependencies:)
        deps = if reader_dependencies.is_a?(Rendering::ReaderRenderCoordinator::Dependencies)
                 reader_dependencies
               else
                 attrs = reader_dependencies.respond_to?(:to_h) ? reader_dependencies.to_h : reader_dependencies
                 Rendering::ReaderRenderCoordinator::Dependencies.new(**attrs)
               end
        Rendering::ReaderRenderCoordinator.new(
          dependencies: deps
        )
      end
    end
  end
end
