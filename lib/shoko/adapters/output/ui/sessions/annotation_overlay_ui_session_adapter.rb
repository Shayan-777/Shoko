# frozen_string_literal: true

require_relative '../../../../core/ports/annotation_overlay_ui_session'
require_relative '../../../input/key_definitions'

module Shoko
  module Adapters
    module Output
      module Ui
        module Sessions
          # Adapter-owned lifecycle for annotations/editor overlays.
          class AnnotationOverlayUiSessionAdapter
            include Core::Ports::AnnotationOverlayUiSession

            def initialize(reader_state_reader:, state_writer:, ui_component_factory:)
              @reader_state_reader = reader_state_reader
              @state_writer = state_writer
              @ui_component_factory = ui_component_factory
            end

            def annotations_visible?
              overlay = annotations_overlay
              overlay.respond_to?(:visible?) && overlay.visible?
            rescue StandardError
              false
            end

            def annotation_editor_visible?
              overlay = annotation_editor_overlay
              overlay.respond_to?(:visible?) && overlay.visible?
            rescue StandardError
              false
            end

            def toggle_annotations
              annotations_visible? ? close_annotations : open_annotations
            end

            def open_annotations
              overlay = @ui_component_factory&.annotations_overlay(@reader_state_reader)
              return false unless overlay

              @state_writer.update_reader(annotations_overlay: overlay)
              true
            rescue StandardError
              false
            end

            def close_annotations
              annotations_overlay&.hide
              @state_writer.update_reader(annotations_overlay: nil)
              true
            rescue StandardError
              false
            end

            def annotations_up
              key = Adapters::Input::KeyDefinitions::NAVIGATION[:up].first
              dispatch_annotations_key(key)
            end

            def annotations_down
              key = Adapters::Input::KeyDefinitions::NAVIGATION[:down].first
              dispatch_annotations_key(key)
            end

            def annotations_open
              annotation = current_annotation
              return nil unless annotation

              { type: :open, annotation: annotation }
            end

            def annotations_edit
              annotation = current_annotation
              return nil unless annotation

              { type: :edit, annotation: annotation }
            end

            def annotations_delete
              annotation = current_annotation
              return nil unless annotation

              { type: :delete, annotation: annotation }
            end

            def annotations_cancel
              { type: :close }
            end

            def set_annotations_selected_index(index)
              overlay = annotations_overlay
              return false unless overlay&.respond_to?(:selected_index=)

              overlay.selected_index = index
              true
            rescue StandardError
              false
            end

            def open_editor(text:, range:, chapter_index:, annotation: nil)
              overlay = @ui_component_factory&.annotation_editor_overlay(
                selected_text: text,
                range: range,
                chapter_index: chapter_index,
                annotation: annotation
              )
              return false unless overlay

              @state_writer.update_reader(annotation_editor_overlay: overlay)
              true
            rescue StandardError
              false
            end

            def close_editor
              annotation_editor_overlay&.hide
              @state_writer.update_reader(annotation_editor_overlay: nil)
              true
            rescue StandardError
              false
            end

            def editor_insert_char(char)
              overlay = annotation_editor_overlay
              return nil unless overlay&.respond_to?(:handle_character)

              overlay.handle_character(char.to_s)
              nil
            rescue StandardError
              nil
            end

            def editor_backspace
              overlay = annotation_editor_overlay
              return nil unless overlay&.respond_to?(:handle_backspace)

              overlay.handle_backspace
              nil
            rescue StandardError
              nil
            end

            def editor_enter
              overlay = annotation_editor_overlay
              return nil unless overlay&.respond_to?(:handle_enter)

              overlay.handle_enter
              nil
            rescue StandardError
              nil
            end

            def editor_move_left
              overlay = annotation_editor_overlay
              return nil unless overlay&.respond_to?(:handle_move_left)

              overlay.handle_move_left
              nil
            rescue StandardError
              nil
            end

            def editor_move_right
              overlay = annotation_editor_overlay
              return nil unless overlay&.respond_to?(:handle_move_right)

              overlay.handle_move_right
              nil
            rescue StandardError
              nil
            end

            def editor_move_up
              overlay = annotation_editor_overlay
              return nil unless overlay&.respond_to?(:handle_move_up)

              overlay.handle_move_up
              nil
            rescue StandardError
              nil
            end

            def editor_move_down
              overlay = annotation_editor_overlay
              return nil unless overlay&.respond_to?(:handle_move_down)

              overlay.handle_move_down
              nil
            rescue StandardError
              nil
            end

            def editor_cancel
              { type: :cancel }
            end

            def editor_save
              overlay = annotation_editor_overlay
              return nil unless overlay&.respond_to?(:handle_save)

              overlay.handle_save
            rescue StandardError
              nil
            end

            def handle_editor_click(col, row)
              overlay = annotation_editor_overlay
              return nil unless overlay&.respond_to?(:handle_click)

              overlay.handle_click(col, row)
            rescue StandardError
              nil
            end

            def editor_context
              overlay = annotation_editor_overlay
              return nil unless overlay

              {
                annotation_id: read_attr(overlay, :annotation_id),
                selected_text: read_attr(overlay, :selected_text),
                note: read_attr(overlay, :note),
                selection_range: read_attr(overlay, :selection_range),
                chapter_index: read_attr(overlay, :chapter_index),
              }
            rescue StandardError
              nil
            end

            private

            def annotations_overlay
              @reader_state_reader&.annotations_overlay
            rescue StandardError
              nil
            end

            def annotation_editor_overlay
              @reader_state_reader&.annotation_editor_overlay
            rescue StandardError
              nil
            end

            def read_attr(target, key)
              target.respond_to?(key) ? target.public_send(key) : nil
            rescue StandardError
              nil
            end

            def current_annotation
              overlay = annotations_overlay
              return nil unless overlay&.respond_to?(:current_annotation)

              overlay.current_annotation
            rescue StandardError
              nil
            end

            def dispatch_annotations_key(key)
              overlay = annotations_overlay
              return nil unless overlay&.respond_to?(:handle_key)

              overlay.handle_key(key)
            rescue StandardError
              nil
            end
          end
        end
      end
    end
  end
end
