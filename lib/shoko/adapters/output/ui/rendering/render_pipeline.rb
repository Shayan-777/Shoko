# frozen_string_literal: true

require_relative '../../../../application/selectors/reader_selectors'

module Shoko
  module Adapters::Output::Ui
    module Rendering
      # RenderPipeline encapsulates the high-level rendering steps for
      # component-driven frames and full-screen mode components.
      class RenderPipeline
        def initialize(dependencies)
          @dependencies = dependencies
          @state = @dependencies.resolve(:global_state)
        end

        # Render the standard layout + overlay path
        def render_layout(surface, bounds, layout, overlay)
          # Clear rendered lines for the new frame so overlays can rely on state
          @state.dispatch(Shoko::Application::Actions::ClearRenderedLinesAction.new)

          dim_layout = annotation_overlay_active?

          begin
            if dim_layout
              surface.with_dimmed { layout.render(surface, bounds) }
            else
              layout.render(surface, bounds)
            end
          rescue StandardError => e
            log_render_error('layout', e)
          end

          begin
            overlay.render(surface, bounds)
          rescue StandardError => e
            log_render_error('overlay', e)
          end
        end

        # Render a dedicated full-screen component (e.g., editor)
        def render_mode_component(component, surface, bounds)
          surface.fill(bounds, ' ')
          component.render(surface, bounds)
        rescue StandardError => e
          log_render_error('mode_component', e)
        end

        # Generic component render helper for non-reader screens (menu, dialogs)
        def render_component(surface, bounds, component)
          surface.fill(bounds, ' ')
          component.render(surface, bounds)
        rescue StandardError => e
          log_render_error('component', e)
        end

        private

        def annotation_overlay_active?
          overlay = Shoko::Application::Selectors::ReaderSelectors.annotation_editor_overlay(@state)
          overlay.respond_to?(:visible?) && overlay.visible?
        rescue StandardError
          false
        end

        def log_render_error(component_name, error)
          logger = begin
            @dependencies.resolve(:logger)
          rescue StandardError
            nil
          end
          logger&.error("render_pipeline.#{component_name}_error",
                        error: error.class.name,
                        message: error.message,
                        backtrace: error.backtrace&.first(5)&.join("\n"))
        end
      end
    end
  end
end
