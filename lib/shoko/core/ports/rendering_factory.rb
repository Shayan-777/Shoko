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
        # @param dependencies [Object] Dependency container or keyword deps
        # @return [Object] Frame coordinator instance
        def create_frame_coordinator(dependencies)
          raise NotImplementedError, "#{self.class} must implement #create_frame_coordinator"
        end

        # Create a render pipeline for diff-based screen updates
        #
        # @param dependencies [Object] Dependency container or keyword deps
        # @return [Object] Render pipeline instance
        def create_render_pipeline(dependencies)
          raise NotImplementedError, "#{self.class} must implement #create_render_pipeline"
        end

        # Create a reader render coordinator for the reading view
        #
        # @param dependencies [Object] Dependencies for rendering
        # @param state [Object] Application state
        # @param opts [Hash] Additional options
        # @return [Object] Reader render coordinator instance
        def create_reader_render_coordinator(dependencies:, state:, **opts)
          raise NotImplementedError, "#{self.class} must implement #create_reader_render_coordinator"
        end
      end
    end
  end
end
