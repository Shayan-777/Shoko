# frozen_string_literal: true

require_relative '../support/session_outcome_helpers'

module Shoko
  module Adapters
    module Ui
      module Sessions
        module AnnotationOverlayUiSession
          # Dispatches annotation editor overlay commands and payload lookups.
          module EditorDispatch
            EDITOR_COMMANDS = {
              editor_insert_char: lambda do |overlay, value|
                overlay.handle_character(value)
                nil
              end,
              editor_backspace: lambda do |overlay, *|
                overlay.handle_backspace
                nil
              end,
              editor_enter: lambda do |overlay, *|
                overlay.handle_enter
                nil
              end,
              editor_move_left: lambda do |overlay, *|
                overlay.handle_move_left
                nil
              end,
              editor_move_right: lambda do |overlay, *|
                overlay.handle_move_right
                nil
              end,
              editor_move_up: lambda do |overlay, *|
                overlay.handle_move_up
                nil
              end,
              editor_move_down: lambda do |overlay, *|
                overlay.handle_move_down
                nil
              end,
              editor_cancel: ->(overlay, *) { overlay.handle_cancel },
              editor_save: ->(overlay, *) { overlay.handle_save },
              editor_spellcheck_target: ->(overlay, *) { overlay.spellcheck_target },
              editor_spell_suggestions_state: ->(overlay, *) { overlay.spell_suggestion_state },
              editor_click: ->(overlay, *args) { overlay.handle_click(*args) },
            }.freeze

            def editor_insert_char(char)
              dispatch_editor_action(:editor_insert_char, char.to_s)
            end

            def editor_backspace
              dispatch_editor_action(:editor_backspace)
            end

            def editor_enter
              dispatch_editor_action(:editor_enter)
            end

            def editor_move_left
              dispatch_editor_action(:editor_move_left)
            end

            def editor_move_right
              dispatch_editor_action(:editor_move_right)
            end

            def editor_move_up
              dispatch_editor_action(:editor_move_up)
            end

            def editor_move_down
              dispatch_editor_action(:editor_move_down)
            end

            def editor_cancel
              dispatch_editor_action(:editor_cancel)
            end

            def editor_save
              dispatch_editor_action(:editor_save)
            end

            def editor_spellcheck_target
              dispatch_editor_action(:editor_spellcheck_target)
            end

            def editor_spell_suggestions_state
              dispatch_editor_action(:editor_spell_suggestions_state)
            end

            def editor_show_spell_suggestions(target:, suggestions:, scope_key: nil, scope_label: nil, can_cycle: false)
              overlay = annotation_editor_overlay
              return spell_suggestions_unavailable unless overlay

              overlay.show_spell_suggestions(
                target,
                suggestions,
                **spell_suggestion_options(scope_key, scope_label, can_cycle)
              )
              success_outcome(:handled, :annotation_editor_spell_suggestions_shown)
            rescue *Support::SessionOutcomeHelpers::RESCUABLE_ERRORS => e
              log_error('annotation.session.editor_show_spell_suggestions', e)
              failure_outcome(:error, :annotation_editor_spell_suggestions_failed, e.message)
            end

            def handle_editor_click(col, row)
              dispatch_editor_action(:editor_click, col, row)
            end

            def editor_context
              overlay = annotation_editor_overlay
              return nil unless overlay

              {
                annotation_id: overlay.annotation_id,
                selected_text: overlay.selected_text,
                note: overlay.note,
                selection_range: overlay.selection_range,
                chapter_index: overlay.chapter_index,
              }
            rescue *Support::SessionOutcomeHelpers::RESCUABLE_ERRORS => e
              log_error('annotation.session.editor_context', e)
              nil
            end

            private

            def spell_suggestions_unavailable
              failure_outcome(
                :ignored,
                :annotation_editor_spell_suggestions_unavailable,
                'Annotation editor overlay unavailable'
              )
            end

            def spell_suggestion_options(scope_key, scope_label, can_cycle)
              {
                scope_key: scope_key,
                scope_label: scope_label,
                can_cycle: can_cycle,
              }
            end

            def dispatch_editor_action(command, *)
              overlay = annotation_editor_overlay
              unless overlay
                return failure_outcome(:ignored, :"#{command}_unavailable", 'Annotation editor overlay unavailable')
              end

              payload = EDITOR_COMMANDS.fetch(command).call(overlay, *)
              success_outcome(:handled, :"#{command}_handled", payload: payload)
            rescue *Support::SessionOutcomeHelpers::RESCUABLE_ERRORS => e
              log_error("annotation.session.#{command}", e)
              failure_outcome(:error, :"#{command}_failed", e.message)
            end
          end
        end
      end
    end
  end
end
