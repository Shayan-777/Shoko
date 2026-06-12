# frozen_string_literal: true

require 'shoko/shared/terminal/text_sanitizer'

module Shoko
  module Adapters
    module Output
      module Terminal
        # Backward-compatible alias for shared terminal text sanitizer primitive.
        #
        # The actual implementation now lives under shared/terminal.
        # This module delegates calls to the shared implementation so
        # existing code continues to work without changes.
        TerminalSanitizer = Shoko::Shared::Terminal::TextSanitizer
      end
    end
  end
end
