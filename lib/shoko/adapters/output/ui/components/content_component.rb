# frozen_string_literal: true

require_relative 'base_component'
require_relative 'surface'
require_relative 'reading/view_renderer_factory'
require_relative 'reading/help_renderer'

module Shoko
  module Adapters::Output::Ui::Components
    # ContentComponent coordinates the main reading content area.
    # It switches between help and the active view renderer based on state.
    class ContentComponent < BaseComponent
      def initialize(controller)
        super(controller&.dependencies) # Initialize BaseComponent with dependencies
        @controller = controller
        @view_renderer = nil
        @reader_state_reader = nil
        deps = controller&.dependencies
        @help_renderer = Reading::HelpRenderer.new(deps)

        state = @controller.state
        # Observe core fields that affect content rendering via StateStore paths
        state.add_observer(self, %i[reader current_chapter], %i[reader left_page], %i[reader right_page],
                           %i[reader single_page], %i[reader current_page_index], %i[reader mode], %i[config view_mode])
      end

      # Observer callback triggered by ObserverStateStore
      def state_changed(path, old_value, new_value)
        # Reset renderer for mode changes or view mode changes
        @view_renderer = nil if [%i[reader mode], %i[config view_mode]].include?(path)

        # Call parent invalidate to properly trigger re-rendering
        super
      end

      # Fill remaining space after fixed components
      def preferred_height(_available_height)
        :fill
      end

      def do_render(surface, bounds)
        case reader_state_reader&.mode
        when :help
          @help_renderer.render(surface, bounds)
        else
          view_renderer.render(surface, bounds)
        end
      end

      private

      def view_renderer
        return @view_renderer if @view_renderer

        @view_renderer = Reading::ViewRendererFactory.create(@controller.state,
                                                             @controller.dependencies)
      end

      def reader_state_reader
        return @reader_state_reader if @reader_state_reader

        deps = @controller&.dependencies
        @reader_state_reader = deps&.resolve(:reader_state_reader)
      rescue StandardError
        nil
      end
    end
  end
end
