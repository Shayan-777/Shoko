# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module Reader
          class IntentRuntimeBridge
            # Maps reader intents onto annotation editor controller commands.
            # Text edits and save/cancel are handled application-side from
            # state; this bridge only carries operations that still need
            # adapter coordination (rendering width for cursor moves,
            # SpellcheckCoordinator, modal exit + overlay teardown).
            module AnnotationActions
              def move_annotation_cursor(direction:)
                case direction
                when :left then controller.annotation_editor_move_left
                when :right then controller.annotation_editor_move_right
                when :up then controller.annotation_editor_move_up
                when :down then controller.annotation_editor_move_down
                end
              end

              def spellcheck_annotation
                controller.annotation_editor_spellcheck
              end

              def close_annotation_editor
                controller.close_annotation_editor_overlay
              end
            end
          end
        end
      end
    end
  end
end
