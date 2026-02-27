# frozen_string_literal: true

module Shoko
  module Adapters
    module Runtime
      module SessionState
        module Selectors
          # Selectors for menu state - provides read-only access to state
          module MenuSelectors
            def self.selected(state)
              state.get(%i[menu selected])
            end

            def self.selected_item(state)
              selected(state)
            end

            def self.mode(state)
              state.get(%i[menu mode])
            end

            def self.browse_selected(state)
              state.get(%i[menu browse_selected])
            end

            def self.search_query(state)
              state.get(%i[menu search_query]) || ''
            end

            def self.search_cursor(state)
              state.get(%i[menu search_cursor])
            end

            def self.search_active(state)
              state.get(%i[menu search_active])
            end

            def self.search_active?(state)
              search_active(state)
            end

            def self.download_query(state)
              state.get(%i[menu download_query]) || ''
            end

            def self.download_cursor(state)
              state.get(%i[menu download_cursor])
            end

            def self.download_selected(state)
              state.get(%i[menu download_selected])
            end

            def self.download_status(state)
              state.get(%i[menu download_status])
            end

            def self.download_progress(state)
              state.get(%i[menu download_progress])
            end

            def self.dictionary_selected(state)
              state.get(%i[menu dictionary_selected])
            end

            def self.dictionary_query(state)
              state.get(%i[menu dictionary_query]) || ''
            end

            def self.dictionary_cursor(state)
              state.get(%i[menu dictionary_cursor])
            end

            def self.dictionary_status(state)
              state.get(%i[menu dictionary_status])
            end

            def self.dictionary_progress(state)
              state.get(%i[menu dictionary_progress])
            end
          end
        end
      end
    end
  end
end
