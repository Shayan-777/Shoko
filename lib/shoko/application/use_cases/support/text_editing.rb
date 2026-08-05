# frozen_string_literal: true

require 'shoko/core/services/text_buffer_edit'

module Shoko
  module Application
    module UseCases
      module Support
        # Stateless helpers for editable text inputs stored in state readers/writers.
        module TextEditing
          module_function

          def apply_edit(current_text, cursor, operation, text: nil)
            safe_text = current_text.to_s
            case operation
            when :insert
              Shoko::Core::Services::TextBufferEdit.insert_at(safe_text, cursor, text.to_s, literal: true)
            when :backspace
              Shoko::Core::Services::TextBufferEdit.backspace_at(safe_text, cursor)
            when :delete
              Shoko::Core::Services::TextBufferEdit.delete_at(safe_text, cursor)
            else
              [safe_text, Shoko::Core::Services::GraphemeCursor.clamp(safe_text, cursor)]
            end
          end
        end
      end
    end
  end
end
