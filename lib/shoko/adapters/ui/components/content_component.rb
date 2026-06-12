# frozen_string_literal: true

require_relative 'base_component'
require_relative 'surface'
require_relative '../rendering/views/view_renderer_factory'
require_relative '../rendering/views/help_renderer'

module Shoko
  module Adapters
    module Ui
      module Components
        # ContentComponent coordinates the main reading content area.
        # It switches between help and the active view renderer based on state.
        class ContentComponent < BaseComponent
          # The two fields whose change must rebuild the cached view renderer;
          # everything else is read live from state on each frame.
          OBSERVED_PATHS = [
            %i[reader mode],
            %i[config view_mode],
          ].freeze

          def initialize(controller:, render_dependencies:)
            super(render_dependencies)
            @controller = controller
            @render_dependencies = render_dependencies
            @view_renderer = nil
            @help_renderer = Reading::HelpRenderer.new(@render_dependencies)

            @render_dependencies.observer_registry.add_observer(self, *OBSERVED_PATHS)
          end

          # Observer callback triggered by ObserverStateStore: drop the cached
          # renderer so the next frame builds one for the new mode/view.
          def state_changed(_path, _old_value, _new_value)
            @view_renderer = nil
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
  end
end
