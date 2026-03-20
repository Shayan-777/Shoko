# frozen_string_literal: true

module Shoko
  module Core
    module Models
      module Session
        # Canonical config and UI session field lists.
        module Schema
          CONFIG_FIELDS = %i[
            schema_version
            view_mode
            line_spacing
            download_source
            page_numbering_mode
            theme
            show_page_numbers
            highlight_quotes
            highlight_keywords
            prefetch_pages
            kitty_images
            dictionary_source_lang
            dictionary_target_lang
            dictionary_path
            dictionary_backend
          ].freeze

          UI_FIELDS = %i[terminal_width terminal_height loading_active loading_message loading_progress].freeze

          UI_BACKED_READER_FIELDS = %i[loading_active loading_message loading_progress].freeze
        end
      end
    end
  end
end
