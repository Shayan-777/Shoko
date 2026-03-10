# frozen_string_literal: true

require_relative '../../requests/cursor_move'
require_relative '../../requests/text_input'
require_relative '../../support/intent_action_group'

module Shoko
  module Application
    module UseCases
      module Reader
        module Actions
          class AnnotationEditor
            include Shoko::Application::UseCases::Support::IntentActionGroup

            SUPPORTED_INTENTS = %i[
              annotation_editor_insert_text
              annotation_editor_backspace
              annotation_editor_newline
              annotation_editor_move_left
              annotation_editor_move_right
              annotation_editor_move_up
              annotation_editor_move_down
              annotation_editor_save
              annotation_editor_cancel
              annotation_editor_spellcheck
            ].freeze

            def initialize(reader_annotation_editor_control:)
              @reader_annotation_editor_control = reader_annotation_editor_control
            end

            def call(intent, payload = nil)
              case intent
              when :annotation_editor_insert_text
                @reader_annotation_editor_control.append_annotation_text(text_from(payload, intent))
              when :annotation_editor_backspace
                validate_payload!(intent, payload)
                @reader_annotation_editor_control.delete_annotation_character
              when :annotation_editor_newline
                validate_payload!(intent, payload)
                @reader_annotation_editor_control.insert_annotation_newline
              when :annotation_editor_move_left
                @reader_annotation_editor_control.move_annotation_cursor(direction: direction_from(payload, intent))
              when :annotation_editor_move_right
                @reader_annotation_editor_control.move_annotation_cursor(direction: direction_from(payload, intent))
              when :annotation_editor_move_up
                @reader_annotation_editor_control.move_annotation_cursor(direction: direction_from(payload, intent))
              when :annotation_editor_move_down
                @reader_annotation_editor_control.move_annotation_cursor(direction: direction_from(payload, intent))
              when :annotation_editor_save
                validate_payload!(intent, payload)
                @reader_annotation_editor_control.save_annotation
              when :annotation_editor_cancel
                validate_payload!(intent, payload)
                @reader_annotation_editor_control.cancel_annotation
              when :annotation_editor_spellcheck
                validate_payload!(intent, payload)
                @reader_annotation_editor_control.spellcheck_annotation
              else
                raise ArgumentError, "unsupported reader annotation editor intent: #{intent}"
              end

              :handled
            end

            private

            def supported_payloads
              {
                annotation_editor_insert_text: [Shoko::Application::UseCases::Requests::TextInput],
                annotation_editor_backspace: [NilClass],
                annotation_editor_newline: [NilClass],
                annotation_editor_move_left: [Shoko::Application::UseCases::Requests::CursorMove],
                annotation_editor_move_right: [Shoko::Application::UseCases::Requests::CursorMove],
                annotation_editor_move_up: [Shoko::Application::UseCases::Requests::CursorMove],
                annotation_editor_move_down: [Shoko::Application::UseCases::Requests::CursorMove],
                annotation_editor_save: [NilClass],
                annotation_editor_cancel: [NilClass],
                annotation_editor_spellcheck: [NilClass],
              }
            end
          end
        end
      end
    end
  end
end
