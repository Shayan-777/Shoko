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
      def initialize(controller:, render_dependencies:)
        super(render_dependencies)
        @controller = controller
        @render_dependencies = render_dependencies
        @view_renderer = nil
        @help_renderer = Reading::HelpRenderer.new(@render_dependencies)

        observer_registry = @render_dependencies.observer_registry
        # Observe core fields that affect content rendering via ObserverRegistry
        observer_registry.add_observer(self, %i[reader current_chapter], %i[reader left_page], %i[reader right_page],
                                       %i[reader single_page], %i[reader current_page_index], %i[reader mode],
                                       %i[config view_mode])
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

        @view_renderer = Reading::ViewRendererFactory.create(@render_dependencies)
      end

      def reader_state_reader
        @render_dependencies.reader_state_reader
      end
    end
  end
end
