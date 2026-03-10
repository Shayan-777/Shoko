# frozen_string_literal: true

module Shoko
  module Application
    module Services
      module Reader
        module Navigation
          # Applies dynamic-mode changes via the reader session store.
          class DynamicChangeApplier
            def initialize(reader_session_store:, page_calculator:, state_updater:)
              @reader_session_store = reader_session_store
              @page_calculator = page_calculator
              @state_updater = state_updater
            end

            def apply(changes)
              return if changes.nil? || changes.empty?

              update_page_index(changes[:current_page_index]) if changes.key?(:current_page_index)

              return unless changes.key?(:current_chapter)

              @state_updater.apply(current_chapter: changes[:current_chapter])
            end

            private

            def update_page_index(new_index)
              updates = { current_page_index: new_index }
              page = @page_calculator&.get_page(new_index)
              if page
                current_chapter = page[:chapter_index]
                current_chapter ||= current_chapter_from_state || 0
                updates[:current_chapter] = current_chapter
              end

              @state_updater.apply(updates)
            end

            def current_chapter_from_state
              @reader_session_store.load.current_chapter
            end
          end
        end
      end
    end
  end
end
