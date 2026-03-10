# frozen_string_literal: true

module Shoko
  module Application
    module UseCases
      module Support
        # Stateless helpers for editable text inputs stored in state readers/writers.
        module TextEditing
          module_function

          def apply_edit(current_text, cursor, operation, text: nil)
            safe_text = current_text.to_s
            safe_cursor = cursor.to_i.clamp(0, safe_text.length)

            case operation
            when :insert
              insert_text(safe_text, safe_cursor, text)
            when :backspace
              backspace_text(safe_text, safe_cursor)
            when :delete
              delete_text(safe_text, safe_cursor)
            else
              [safe_text, safe_cursor]
            end
          end

          def insert_text(current_text, cursor, text)
            insert = text.to_s
            return [current_text, cursor] if insert.empty?

            [current_text[0, cursor].to_s + insert + current_text[cursor..].to_s, cursor + insert.length]
          end
          private_class_method :insert_text

          def backspace_text(current_text, cursor)
            return [current_text, cursor] if cursor <= 0

            previous_cursor = cursor - 1
            [current_text[0, previous_cursor].to_s + current_text[cursor..].to_s, previous_cursor]
          end
          private_class_method :backspace_text

          def delete_text(current_text, cursor)
            return [current_text, cursor] if cursor >= current_text.length

            [current_text[0, cursor].to_s + current_text[(cursor + 1)..].to_s, cursor]
          end
          private_class_method :delete_text
        end
      end
    end
  end
end
