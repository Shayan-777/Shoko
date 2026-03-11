# frozen_string_literal: true

module Shoko
  module Core
    module Models
      module Session
        ConfigSnapshotFields = %i[
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

        # Immutable application configuration snapshot.
        class ConfigSnapshot < Data.define(*ConfigSnapshotFields)
          SCHEMA_VERSION = 2

          DEFAULTS = {
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
            dictionary_source_lang: 'auto',
            dictionary_target_lang: 'en',
            dictionary_path: nil,
            dictionary_backend: nil,
          }.freeze

          def self.build(attributes = {})
            new(**DEFAULTS.merge(attributes))
          end

          def self.from_state(config_state)
            build(config_state || {})
          end

          def with(**attributes)
            self.class.build(to_h.merge(attributes))
          end

          def to_state_updates
            to_h.each_with_object({}) do |(field, value), updates|
              updates[[:config, field]] = value
            end
          end
        end
      end
    end
  end
end
