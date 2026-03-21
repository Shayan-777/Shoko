# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module MouseableReaderSupport
          # Exposes popup visibility and reader-session refresh helpers for mouseable readers.
          module PopupStateSupport
            private

            def dictionary_popup_visible?
              popup_ui_controller&.dictionary_visible? == true
            end

            def annotation_editor_visible?
              popup_ui_controller&.annotation_editor_visible? == true
            end

            def in_book_search_popup_visible?
              popup_ui_controller&.in_book_search_visible? == true
            end

            def translation_popup_visible?
              controller = popup_ui_controller
              controller&.respond_to?(:translation_popup_visible?) && controller.translation_popup_visible?
            end

            def popup_menu_active?
              @reader_state_reader.popup_menu&.visible
            end

            def popup_ui_controller
              controllers&.ui_controller
            end

            def refresh_annotations
              annotations = @annotation_service_ref.list_for_book(path)
              @reader_session_mutator.update_reader(annotations: annotations)
            end

            def clear_rendered_lines_on_init
              @render_state_writer.clear_rendered_lines
            end
          end
        end
      end
    end
  end
end
