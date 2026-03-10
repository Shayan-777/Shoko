# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module Reader
          class IntentRuntimeBridge
            module AnnotationActions
              def append_annotation_text(text)
                controller.annotation_editor_insert_char(text.to_s)
              end

              def delete_annotation_character
                controller.annotation_editor_backspace
              end

              def insert_annotation_newline
                controller.annotation_editor_enter
              end

              def move_annotation_cursor(direction:)
                case direction
                when :left then controller.annotation_editor_move_left
                when :right then controller.annotation_editor_move_right
                when :up then controller.annotation_editor_move_up
                when :down then controller.annotation_editor_move_down
                end
              end

              def save_annotation
                controller.annotation_editor_save
              end

              def cancel_annotation
                controller.annotation_editor_cancel
              end

              def spellcheck_annotation
                controller.annotation_editor_spellcheck
              end
            end
          end
        end
      end
    end
  end
end
