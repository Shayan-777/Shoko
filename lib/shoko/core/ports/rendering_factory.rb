# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      # Port interface for creating rendering system components.
      # Adapters implementing this interface should handle instantiation
      # of frame coordinators, render pipelines, and render coordinators.
      module RenderingFactory
        # Create a frame coordinator for managing screen layout regions
        #
        # @param terminal_service [Object]
        # @param global_state [Object]
        # @param ui_state_reader [Object]
        # @return [Object] Frame coordinator instance
        def create_frame_coordinator(terminal_service:, global_state:, ui_state_reader:)
          raise NotImplementedError, "#{self.class} must implement #create_frame_coordinator"
        end

        # Create a render pipeline for diff-based screen updates
        #
        # @param global_state [Object]
        # @param reader_state_reader [Object]
        # @param logger [Object, nil]
        # @return [Object] Render pipeline instance
        def create_render_pipeline(global_state:, reader_state_reader:, logger: nil)
          raise NotImplementedError, "#{self.class} must implement #create_render_pipeline"
        end

        # Create a reader render coordinator for the reading view
        #
        # @param reader_dependencies [Object] Typed dependencies for rendering
        # @return [Object] Reader render coordinator instance
        def create_reader_render_coordinator(reader_dependencies:)
          raise NotImplementedError, "#{self.class} must implement #create_reader_render_coordinator"
        end
      end
    end
  end
end
