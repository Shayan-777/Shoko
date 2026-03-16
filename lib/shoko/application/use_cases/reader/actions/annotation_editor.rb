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
              dispatch_route(intent, payload, routes, unsupported: 'unsupported reader annotation editor intent')
            end

            private

            def routes
              @routes ||= {
                annotation_editor_insert_text: route(payload: :text, result: :handled) do |text|
                  @reader_annotation_editor_control.append_annotation_text(text)
                end,
                annotation_editor_backspace: route(result: :handled) do
                  @reader_annotation_editor_control.delete_annotation_character
                end,
                annotation_editor_newline: route(result: :handled) do
                  @reader_annotation_editor_control.insert_annotation_newline
                end,
                annotation_editor_move_left: route(payload: :direction, result: :handled) do |direction|
                  @reader_annotation_editor_control.move_annotation_cursor(direction: direction)
                end,
                annotation_editor_move_right: route(payload: :direction, result: :handled) do |direction|
                  @reader_annotation_editor_control.move_annotation_cursor(direction: direction)
                end,
                annotation_editor_move_up: route(payload: :direction, result: :handled) do |direction|
                  @reader_annotation_editor_control.move_annotation_cursor(direction: direction)
                end,
                annotation_editor_move_down: route(payload: :direction, result: :handled) do |direction|
                  @reader_annotation_editor_control.move_annotation_cursor(direction: direction)
                end,
                annotation_editor_save: route(result: :handled) { @reader_annotation_editor_control.save_annotation },
                annotation_editor_cancel: route(result: :handled) { @reader_annotation_editor_control.cancel_annotation },
                annotation_editor_spellcheck: route(result: :handled) do
                  @reader_annotation_editor_control.spellcheck_annotation
                end,
              }.freeze
            end

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
