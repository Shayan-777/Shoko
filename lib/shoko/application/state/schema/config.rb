# frozen_string_literal: true

module Shoko
  module Application
    module State
      module Schema
        # Application-owned configuration schema fragment.
        #
        # Owns `state[:config]`: user-controlled preferences that survive
        # process restarts via the config-storage adapter. The fragment requires
        # a `terminal_capabilities` context entry to derive defaults for
        # capability-gated preferences (e.g. inline images).
        module Config
          PARTITION = :config

          SCHEMA_VERSION = 2

          FIELDS = %i[
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
            prepaginate_on_resize
            last_paginated_size
            dictionary_source_lang
            dictionary_target_lang
            dictionary_path
            dictionary_backend
            paragraph_style
            justify
            book_colors
          ].freeze

          BASE_DEFAULTS = {
            schema_version: SCHEMA_VERSION,
            view_mode: :single,
            line_spacing: :normal,
            download_source: :gutendex,
            page_numbering_mode: :dynamic,
            theme: :default,
            show_page_numbers: true,
            highlight_quotes: true,
            highlight_keywords: false,
            prefetch_pages: 20,
            kitty_images: false,
            # When on, the library pre-paginates cached books on startup after a
            # terminal-size change so opening them is instant. last_paginated_size
            # ("WxH") is the size that pre-pagination last ran for; it gates the
            # batch so it only runs when the size actually changed.
            prepaginate_on_resize: false,
            last_paginated_size: nil,
            dictionary_source_lang: 'auto',
            dictionary_target_lang: 'en',
            dictionary_path: nil,
            dictionary_backend: nil,
            # Typesetting: paragraph_style follows the book's own design by
            # default (spaced/indent force the classic modes); justify adds
            # full justification; book_colors toggles book-specified colors.
            paragraph_style: :book,
            justify: :book,
            book_colors: true,
          }.freeze

          DEFAULTS = BASE_DEFAULTS

          module_function

          def contribute(context = {})
            terminal_capabilities = context[:terminal_capabilities]
            raise ArgumentError, 'terminal_capabilities is required for Config schema' if terminal_capabilities.nil?

            { PARTITION => BASE_DEFAULTS.merge(kitty_images: terminal_capabilities.kitty_graphics_supported?) }
          end
        end
      end
    end
  end
end
