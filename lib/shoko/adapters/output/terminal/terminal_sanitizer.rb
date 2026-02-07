# frozen_string_literal: true

require_relative '../../../shared/text_sanitizer'

module Shoko
  module Adapters
    module Output
      module Terminal
        # Backward-compatible alias for Shoko::Shared::TextSanitizer.
        #
        # The actual implementation now lives in shared/text_sanitizer.rb.
        # This module delegates all calls to the shared implementation so
        # existing code continues to work without changes.
        TerminalSanitizer = Shoko::Shared::TextSanitizer
      end
    end
  end
end
