# frozen_string_literal: true

require_relative '../../core/book_formats/format_registry'

module Shoko
  module Adapters::BookSources
    # Backward-compatible alias for Shoko::Core::BookFormats::FormatRegistry.
    #
    # The actual implementation now lives in core/book_formats/format_registry.rb.
    FormatRegistry = Shoko::Core::BookFormats::FormatRegistry
  end
end
