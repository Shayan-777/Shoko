# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module Reader
          class IntentRuntimeBridge
            module AnnotationActions
              def annotation_editor_insert_text(text)
                controller.annotation_editor_insert_char(text.to_s)
              end

              def annotation_editor_backspace
                controller.annotation_editor_backspace
              end

              def annotation_editor_newline
                controller.annotation_editor_enter
              end

              def annotation_editor_move(direction)
                case direction
                when :left then controller.annotation_editor_move_left
                when :right then controller.annotation_editor_move_right
                when :up then controller.annotation_editor_move_up
                when :down then controller.annotation_editor_move_down
                end
              end

              def annotation_editor_save
                controller.annotation_editor_save
              end

              def annotation_editor_cancel
                controller.annotation_editor_cancel
              end

              def annotation_editor_spellcheck
                controller.annotation_editor_spellcheck
              end
            end
          end
        end
      end
    end
  end
end
