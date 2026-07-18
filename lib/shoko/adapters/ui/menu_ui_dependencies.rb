# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      # Typed dependencies used by menu-facing UI adapters.
      MenuUiDependencies = Data.define(
        :menu_state_reader,
        :menu_session_mutator,
        :reader_state_reader,
        :config_reader,
        :runtime_config,
        :dictionary_availability,
        :dictionary_storage,
        :annotation_service,
        :catalog_service,
        :rss_reader_service,
        :menu_hit_registry,
        :reader_launch_state,
        :document
      )
    end
  end
end
