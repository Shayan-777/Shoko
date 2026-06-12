# frozen_string_literal: true

require 'shoko/shared/annotation_list_input'
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

          def apply(op)
            case op.operation
            when :insert then insert_text(op.text)
            when :backspace then delete_character
            when :delete then delete_forward
            when :newline then insert_newline
            end
          end

          private

          def insert_text(char)
            return unless Shoko::Shared::TextSanitizer.printable_char?(char.to_s)

            text, cursor = Shoko::Shared::AnnotationListInput.insert_character(current_text, current_cursor, char)
            @writer.call(text: text, cursor: cursor)
          end

          def delete_character
            cursor = current_cursor
            return if cursor.zero?

            text = current_text
            new_text = text[0...(cursor - 1)] + text[cursor..].to_s
            @writer.call(text: new_text, cursor: cursor - 1)
          end

          def delete_forward
            cursor = current_cursor
            text = current_text
            return if cursor >= text.length

            new_text = text[0...cursor] + text[(cursor + 1)..].to_s
            @writer.call(text: new_text, cursor: cursor)
          end

          def insert_newline
            text, cursor = Shoko::Shared::AnnotationListInput.insert_newline(current_text, current_cursor)
            @writer.call(text: text, cursor: cursor)
          end

          def current_text
            (@text_reader.call || '').to_s
          end

          def current_cursor
            value = @cursor_reader.call
            value.nil? ? current_text.length : value.to_i.clamp(0, current_text.length)
          end
        end
      end
    end
  end
end
