# frozen_string_literal: true

module Shoko
  module Application
    module Ports
      # Port interface for creating rendering system components.
      # Adapters implementing this interface should handle instantiation
      # of frame coordinators, render pipelines, and render coordinators.
      module RenderingFactory
        # Create a frame coordinator for managing screen layout regions.
        def create_frame_coordinator(terminal_service:, state_writer:, ui_state_reader:)
          raise NotImplementedError, "#{self.class} must implement #create_frame_coordinator"
        end

        # Create a render pipeline for diff-based screen updates.
        def create_render_pipeline(reader_state_reader:, logger: nil)
          raise NotImplementedError, "#{self.class} must implement #create_render_pipeline"
        end

        # Create a reader render coordinator for the reading view.
        def create_reader_render_coordinator(reader_dependencies:)
          raise NotImplementedError, "#{self.class} must implement #create_reader_render_coordinator"
        end
      end
    end
  end
end
