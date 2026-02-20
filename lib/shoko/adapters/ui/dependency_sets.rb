# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
        # Typed dependencies used by reader-facing UI adapters.
        ReaderUiDependencies = Data.define(
          :observer_registry,
          :terminal_service,
          :ui_state_reader,
          :reader_state_reader,
          :sidebar_state_reader,
          :config_reader,
          :render_state_writer,
          :rendered_content_reader,
          :notification_service,
          :logger,
          :coordinate_service,
          :view_model_builder_factory,
          :layout_service,
          :layout_metrics,
          :page_calculator,
          :wrapping_service,
          :formatting_service,
          :kitty_image_renderer,
          :runtime_config,
          :reader_session_context,
          :document,
          :annotation_service
        )

        # Typed dependencies used by menu-facing UI adapters.
        MenuUiDependencies = Data.define(
          :menu_state_reader,
          :menu_state_writer,
          :reader_state_reader,
          :sidebar_state_reader,
          :config_reader,
          :runtime_config,
          :dictionary_availability,
          :dictionary_storage,
          :annotation_service,
          :catalog_service,
          :reader_session_context,
          :document
        )
      end
  end
end
