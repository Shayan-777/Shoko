# frozen_string_literal: true

require 'shoko/core/services/annotation_list_input'
require 'shoko/core/services/grapheme_cursor'
require 'shoko/core/services/text_buffer_edit'
require 'shoko/shared/text_sanitizer'

module Shoko
  module Application
    module Services
      module AnnotationEdit
        # Pure text-edit operations for annotation editors. Reads current
        # (text, cursor) via caller-supplied lambdas and writes the
        # result via the supplied callback. The reader and menu editors
        # share this implementation over their own schema-hosted fields.
        class Operator
          # text_reader/cursor_reader: zero-arg lambdas returning the
          #   current text/cursor.
          # writer: lambda accepting (text:, cursor:) that persists both
          #   fields together.
          def initialize(text_reader:, cursor_reader:, writer:)
            @text_reader = text_reader
            @cursor_reader = cursor_reader
            @writer = writer
          end

          def apply(operation)
            case operation.operation
            when :insert then insert_text(operation.text)
            when :backspace then delete_character
            when :delete then delete_forward
            when :newline then insert_newline
            end
          end

          private

          def insert_text(char)
            return unless Shoko::Shared::TextSanitizer.printable_char?(char.to_s)

            text, cursor = Shoko::Core::Services::AnnotationListInput.insert_character(current_text, current_cursor,
                                                                                       char)
            @writer.call(text: text, cursor: cursor)
          end

          def delete_character
            cursor = current_cursor
            return if cursor.zero?

            text, cursor = Shoko::Core::Services::TextBufferEdit.backspace_at(current_text, cursor)
            @writer.call(text: text, cursor: cursor)
          end

          def delete_forward
            cursor = current_cursor
            text = current_text
            return if cursor >= text.length

            text, cursor = Shoko::Core::Services::TextBufferEdit.delete_at(text, cursor)
            @writer.call(text: text, cursor: cursor)
          end

          def insert_newline
            text, cursor = Shoko::Core::Services::AnnotationListInput.insert_newline(current_text, current_cursor)
            @writer.call(text: text, cursor: cursor)
          end

          def current_text
            (@text_reader.call || '').to_s
          end

          def current_cursor
            value = @cursor_reader.call
            return current_text.length if value.nil?

            Shoko::Core::Services::GraphemeCursor.clamp(current_text, value)
          end
        end
      end
    end
  end
end
