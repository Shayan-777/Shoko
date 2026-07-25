# frozen_string_literal: true

require_relative 'text_sanitizer'

module Shoko
  module Shared
    # Caret-relative edits on a flat text buffer.
    #
    # Each operation takes the current text and caret offset and returns the
    # new `[text, cursor]` pair, leaving both unchanged when the edit is not
    # applicable (caret at a boundary, or a non-printable character). The notes
    # editor and the translator's source pane drive the same single-line buffer
    # model, so the edit rules live here once.
    module TextBufferEdit
      module_function

      # @param literal [Boolean] insert without the printability check (used
      #   for pasted content, which is sanitized at its own boundary)
      # @return [Array(String, Integer)]
      def insert_at(text, cursor, char, literal: false)
        return [text, cursor] unless literal || TextSanitizer.printable_char?(char)

        ["#{text[0...cursor]}#{char}#{text[cursor..]}", cursor + char.length]
      end

      # @return [Array(String, Integer)]
      def backspace_at(text, cursor)
        return [text, cursor] if cursor <= 0

        ["#{text[0...(cursor - 1)]}#{text[cursor..]}", cursor - 1]
      end

      # Applies an editor operation (an EditOp-shaped object carrying
      # #operation and, for inserts, #text) to the buffer. The notes editor and
      # the translator source pane drive the identical operation set.
      #
      # @return [Array(String, Integer)]
      def apply(text, cursor, edit_op)
        case edit_op&.operation
        when :insert    then insert_at(text, cursor, edit_op.text.to_s)
        when :newline   then insert_at(text, cursor, "\n", literal: true)
        when :backspace then backspace_at(text, cursor)
        when :delete    then delete_at(text, cursor)
        else [text, cursor]
        end
      end

      # @return [Array(String, Integer)]
      def delete_at(text, cursor)
        return [text, cursor] if cursor >= text.length

        ["#{text[0...cursor]}#{text[(cursor + 1)..]}", cursor]
      end
    end
  end
end
