# frozen_string_literal: true

require_relative '../../../core/ports/text_sanitizer'
require_relative 'terminal_sanitizer'

module Shoko
  module Adapters::Output::Terminal
    # Adapter implementing the TextSanitizer port.
    # Delegates to TerminalSanitizer for safe text rendering.
    class TextSanitizerAdapter
      include Core::Ports::TextSanitizer

      def sanitize(text, preserve_newlines: true, max_length: nil)
        sanitized = TerminalSanitizer.sanitize(text.to_s, preserve_newlines: preserve_newlines)
        max_length ? sanitized[0, max_length] : sanitized
      end
    end
  end
end
