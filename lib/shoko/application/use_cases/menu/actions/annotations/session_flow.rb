# frozen_string_literal: true

module Shoko
  module Application
    module UseCases
      module Menu
        module Actions
          class Annotations
            module SessionFlow
              private

              def open_annotations_mode
                preload_annotations
                @menu_session_mutator.update_menu(mode: :annotations, browse_selected: 0)
                @menu_runtime.activate_mode(:annotations)
                :handled
              end

              def activate_annotation_selection
                context = @menu_runtime.selected_annotation_context
                return :pass unless context && context[:annotation] && context[:book_path]

                @menu_session_mutator.update_menu(
                  selected_annotation: context[:annotation],
                  selected_annotation_book: context[:book_path],
                  mode: :annotation_detail,
                  browse_selected: 0
                )
                @menu_runtime.activate_mode(:annotation_detail)
                :handled
              end

              def save_annotation_edit
                @menu_runtime.annotation_editor_save
                @menu_session_mutator.update_menu(mode: :annotations)
                @menu_runtime.activate_mode(:annotations)
                :handled
              end

              def cancel_annotation_edit
                @menu_runtime.annotation_editor_cancel
                @menu_session_mutator.update_menu(mode: :annotations)
                @menu_runtime.activate_mode(:annotations)
                :handled
              end

              def preload_annotations
                annotations = @annotation_service ? @annotation_service.list_all : {}
                @menu_session_mutator.update_menu(annotations_all: annotations || {})
              rescue Shoko::Error => e
                @logger&.error('menu.preload_annotations.failed', error: e.class.name, message: e.message)
                @menu_session_mutator.update_menu(annotations_all: {})
              end
            end
          end
        end
      end
    end
  end
end
