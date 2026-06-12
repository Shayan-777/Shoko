# frozen_string_literal: true

require_relative '../../../application/ports/outbound/text_sanitizer'
require_relative 'terminal_sanitizer'

module Shoko
  module Adapters
    module Output
      module Terminal
        # Adapter implementing the TextSanitizer port.
        # Delegates to TerminalSanitizer for safe text rendering.
        class TextSanitizerAdapter
          include Application::Ports::Outbound::TextSanitizer

          def sanitize(text, preserve_newlines: true, max_length: nil)
            sanitized = TerminalSanitizer.sanitize(text.to_s, preserve_newlines: preserve_newlines)
            max_length ? sanitized[0, max_length] : sanitized
          end
        end
      end
    end
  end
end
