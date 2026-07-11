# frozen_string_literal: true

require 'shoko/shared/hash_normalizer'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Menu-state helper for annotation edit screens.
          class AnnotationEditState
            def initialize(dependencies = nil)
              @dependencies = dependencies
              @menu_state_reader = nil
              @menu_session_mutator = nil
            end

            def text
              (menu_state_reader&.annotation_edit_text || '').to_s
            end

            def cursor(text = self.text)
              (menu_state_reader&.annotation_edit_cursor || text.length).to_i
            end

            def update_from
              current_text = text
              current_cursor = cursor(current_text)
              updated = yield(current_text, current_cursor)
              update(text: updated[0], cursor: updated[1]) if updated
            end

            def update(text:, cursor:)
              menu_session_mutator&.update_menu(annotation_edit_text: text, annotation_edit_cursor: cursor)
            end

            def selected_annotation
              ann = menu_state_reader&.selected_annotation
              return unless ann.is_a?(Hash)

              Shoko::Shared::HashNormalizer.symbolize_keys(ann)
            end

            def annotation_update_payload
              annotation = selected_annotation || {}
              path = menu_state_reader&.selected_annotation_book
              ann_id = annotation[:id]
              return nil unless path && ann_id

              { path: path, ann_id: ann_id, text: text }
            end

            def refresh_annotations(service)
              menu_session_mutator&.update_menu(annotations_all: service.list_all)
            end

            def return_to_annotations_list
              menu_session_mutator&.update_menu(mode: :annotations)
            end

            private

            def menu_state_reader
              @menu_state_reader ||= @dependencies&.menu_state_reader
            end

            def menu_session_mutator
              @menu_session_mutator ||= @dependencies&.menu_session_mutator
            end
          end
        end
      end
    end
  end
end
