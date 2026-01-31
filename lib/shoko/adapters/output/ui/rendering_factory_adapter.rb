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

      def create_frame_coordinator(dependencies)
        Rendering::FrameCoordinator.new(dependencies)
      end

      def create_render_pipeline(dependencies)
        Rendering::RenderPipeline.new(dependencies)
      end

      def create_reader_render_coordinator(dependencies:, state:, **)
        Rendering::ReaderRenderCoordinator.new(
          dependencies: Rendering::ReaderRenderCoordinator::Dependencies.new(
            dependencies: dependencies,
            state: state,
            **
          )
        )
      end
    end
  end
end
