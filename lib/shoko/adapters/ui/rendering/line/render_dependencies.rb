# frozen_string_literal: true

module Shoko
  module Presentation
    module Ui
        module Components
          module Reading
            # Typed dependencies shared by reading renderers and helpers.
            RenderDependencies = Data.define(
              :layout_service,
              :layout_metrics,
              :render_state_writer,
              :config_reader,
              :reader_state_reader,
              :rendered_content_reader,
              :logger,
              :observer_registry,
              :reader_session_context,
              :document,
              :page_calculator,
              :formatting_service,
              :wrapping_service,
              :kitty_image_renderer,
              :runtime_config
            )
          end
        end
      end
  end
end
