# frozen_string_literal: true

require_relative '../../requests/cursor_move'
require_relative '../../requests/text_input'
require_relative '../../support/intent_action_group'

module Shoko
  module Application
    module UseCases
      module Reader
        module Actions
          # Routes annotation editor intents to the reader annotation-editor control surface.
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
              dispatch_route(intent, payload, routes, unsupported: 'unsupported reader annotation editor intent')
            end

            private

            def routes
              @routes ||= editor_text_routes.merge(editor_movement_routes).merge(editor_command_routes).freeze
            end

            def supported_payloads
              text_payloads(:annotation_editor_insert_text)
                .merge(nil_payloads(:annotation_editor_backspace,
                                    :annotation_editor_newline,
                                    :annotation_editor_save,
                                    :annotation_editor_cancel,
                                    :annotation_editor_spellcheck))
                .merge(direction_payloads(:annotation_editor_move_left,
                                          :annotation_editor_move_right,
                                          :annotation_editor_move_up,
                                          :annotation_editor_move_down))
                .freeze
            end

            def editor_text_routes
              route_map_for(:annotation_editor_insert_text, payload: :text, result: :handled) do |text|
                @reader_annotation_editor_control.append_annotation_text(text)
              end
            end

            def editor_movement_routes
              route_map_for(
                %i[
                  annotation_editor_move_left
                  annotation_editor_move_right
                  annotation_editor_move_up
                  annotation_editor_move_down
                ],
                payload: :direction,
                result: :handled
              ) do |direction|
                @reader_annotation_editor_control.move_annotation_cursor(direction: direction)
              end
            end

            def editor_command_routes
              handled_routes(:annotation_editor_backspace) do
                @reader_annotation_editor_control.delete_annotation_character
              end
                .merge(handled_routes(:annotation_editor_newline) do
                  @reader_annotation_editor_control.insert_annotation_newline
                end)
                .merge(handled_routes(:annotation_editor_save) { @reader_annotation_editor_control.save_annotation })
                .merge(handled_routes(:annotation_editor_cancel) do
                  @reader_annotation_editor_control.cancel_annotation
                end)
                .merge(handled_routes(:annotation_editor_spellcheck) do
                  @reader_annotation_editor_control.spellcheck_annotation
                end)
            end
          end
        end
      end
    end
  end
end
