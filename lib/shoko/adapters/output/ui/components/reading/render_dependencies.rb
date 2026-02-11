# frozen_string_literal: true

module Shoko
  module Adapters
    module Output
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
              :global_state,
              :reader_session_context,
              :document,
              :page_calculator,
              :formatting_service,
              :wrapping_service,
              :kitty_image_renderer
            )
          end
        end
      end
    end
  end
end
