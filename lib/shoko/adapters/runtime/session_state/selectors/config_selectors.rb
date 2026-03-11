# frozen_string_literal: true

module Shoko
  module Adapters
    module Runtime
      module SessionState
        module Selectors
          # Selectors for configuration state
          module ConfigSelectors
            def self.view_mode(state)
              state.get(%i[config view_mode])
            end

            def self.line_spacing(state)
              state.get(%i[config line_spacing])
            end

            def self.download_source(state)
              state.get(%i[config download_source])
            end

            def self.page_numbering_mode(state)
              state.get(%i[config page_numbering_mode])
            end

            def self.theme(state)
              state.get(%i[config theme])
            end

            def self.show_page_numbers(state)
              state.get(%i[config show_page_numbers])
            end

            def self.show_page_numbers?(state)
              show_page_numbers(state)
            end

            def self.highlight_quotes(state)
              state.get(%i[config highlight_quotes])
            end

            def self.highlight_quotes?(state)
              highlight_quotes(state)
            end

            def self.highlight_keywords(state)
              state.get(%i[config highlight_keywords])
            end

            def self.highlight_keywords?(state)
              highlight_keywords(state)
            end

            def self.kitty_images(state)
              state.get(%i[config kitty_images])
            end

            def self.kitty_images?(state)
              !!kitty_images(state)
            end

            def self.config_hash(state)
              state.get([:config])
            end

            def self.dictionary_source_lang(state)
              state.get(%i[config dictionary_source_lang])
            end

            def self.dictionary_target_lang(state)
              state.get(%i[config dictionary_target_lang])
            end

            def self.dictionary_path(state)
              state.get(%i[config dictionary_path])
            end

            def self.dictionary_backend(state)
              state.get(%i[config dictionary_backend])
            end
          end
        end
      end
    end
  end
end
