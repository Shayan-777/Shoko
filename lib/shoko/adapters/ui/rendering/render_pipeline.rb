# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module Rendering
        # RenderPipeline encapsulates the high-level rendering steps for
        # component-driven frames and full-screen mode components.
        #
        # Note: This component does NOT manage render state mutations.
        # The coordinator (ReaderRenderCoordinator) is responsible for
        # clearing/updating rendered lines state before/after rendering.
        class RenderPipeline
          def initialize(reader_state_reader:, logger: nil)
            @reader_state_reader = reader_state_reader
            @logger = logger
          end

          # Render the standard layout + overlay path
          def render_layout(surface, bounds, layout, overlay)
            dim_layout = annotation_overlay_active?

            begin
              if dim_layout
                surface.with_dimmed { layout.render(surface, bounds) }
              else
                layout.render(surface, bounds)
              end
            rescue Shoko::Error => e
              log_render_error('layout', e)
            end

            begin
              overlay.render(surface, bounds)
            rescue Shoko::Error => e
              log_render_error('overlay', e)
            end
          end

          # Render a dedicated full-screen component (e.g., editor)
          def render_mode_component(component, surface, bounds)
            surface.fill(bounds, ' ')
            component.render(surface, bounds)
          rescue Shoko::Error => e
            log_render_error('mode_component', e)
          end

          # Generic component render helper for non-reader screens (menu, dialogs)
          def render_component(surface, bounds, component)
            surface.fill(bounds, ' ')
            component.render(surface, bounds)
          rescue Shoko::Error => e
            log_render_error('component', e)
          end

          private

          def annotation_overlay_active?
            overlay = @reader_state_reader&.annotation_editor_overlay
            overlay&.visible? == true
          end

          def log_render_error(component_name, error)
            @logger&.error("render_pipeline.#{component_name}_error",
                           error: error.class.name,
                           message: error.message,
                           backtrace: error.backtrace&.first(5)&.join("\n"))
          end
        end
      end
    end
  end
end
