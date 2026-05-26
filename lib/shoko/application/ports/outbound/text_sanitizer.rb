# frozen_string_literal: true

module Shoko
  module Application
    module Ports
      module Outbound
        # Port interface for sanitizing text for safe display.
        # Adapters implementing this interface should handle removing
        # or replacing control characters and unsafe content.
        module TextSanitizer
          # Sanitize text for safe display
          #
          # @param text [String] Text to sanitize
          # @param preserve_newlines [Boolean] Whether to keep newline characters
          # @param max_length [Integer, nil] Maximum output length (nil for unlimited)
          # @return [String] Sanitized text
          def sanitize(text, preserve_newlines: true, max_length: nil)
            raise NotImplementedError, "#{self.class} must implement #sanitize"
          end
        end
      end
    end
  end
end
