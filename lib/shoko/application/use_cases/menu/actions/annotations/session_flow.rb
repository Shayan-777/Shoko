# frozen_string_literal: true

module Shoko
  module Application
    module UseCases
      module Menu
        module Actions
          class Annotations
            # Shared menu-session transitions for annotation browsing and editing.
            module SessionFlow
              private

              def open_annotations_mode
                preload_annotations
                update_menu(mode: :annotations, browse_selected: 0)
                :handled
              end

              def activate_annotation_selection
                context = @menu_annotation_control.selected_annotation_context
                return :pass unless context && context[:annotation] && context[:book_path]

                update_menu(
                  selected_annotation: context[:annotation],
                  selected_annotation_book: context[:book_path],
                  mode: :annotation_detail,
                  browse_selected: 0
                )
                :handled
              end

              def save_annotation_edit
                @annotation_workflow.save_current_annotation_edit
                :handled
              end

              def cancel_annotation_edit
                @annotation_workflow.cancel_current_annotation_edit
                :handled
              end

              def preload_annotations
                annotations = @annotation_service ? @annotation_service.list_all : {}
                update_menu(annotations_all: annotations || {})
              rescue Shoko::Error => e
                @logger&.error('menu.preload_annotations.failed', error: e.class.name, message: e.message)
                update_menu(annotations_all: {})
              end
            end
          end
        end
      end
    end
  end
end
