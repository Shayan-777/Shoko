# frozen_string_literal: true

require 'shoko/shared/text_sanitizer'
require_relative 'grapheme_cursor'

module Shoko
  module Core
    module Services
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
          return [text, cursor] unless literal || Shoko::Shared::TextSanitizer.printable_char?(char)

          safe_text = text.to_s
          safe_cursor = GraphemeCursor.clamp(safe_text, cursor)
          ["#{safe_text[0...safe_cursor]}#{char}#{safe_text[safe_cursor..]}", safe_cursor + char.length]
        end

        # @return [Array(String, Integer)]
        def backspace_at(text, cursor)
          safe_text = text.to_s
          safe_cursor = GraphemeCursor.clamp(safe_text, cursor)
          return [safe_text, safe_cursor] if safe_cursor <= 0

          previous = GraphemeCursor.previous(safe_text, safe_cursor)
          ["#{safe_text[0...previous]}#{safe_text[safe_cursor..]}", previous]
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
          safe_text = text.to_s
          safe_cursor = GraphemeCursor.clamp(safe_text, cursor)
          return [safe_text, safe_cursor] if safe_cursor >= safe_text.length

          following = GraphemeCursor.next(safe_text, safe_cursor)
          ["#{safe_text[0...safe_cursor]}#{safe_text[following..]}", safe_cursor]
        end
      end
    end
  end
end
