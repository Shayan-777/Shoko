# frozen_string_literal: true

require_relative '../../core/book_formats/format_registry'

module Shoko
  module Adapters
    module BookSources
      # Adapter-side probe for filesystem book eligibility checks.
      class BookFileProbe
        def initialize(format_registry: Shoko::Core::BookFormats::FormatRegistry)
          @format_registry = format_registry
        end

        def book_file?(path)
          @format_registry.supported_extension?(path) &&
            File.readable?(path) &&
            File.size(path).positive?
        rescue Shoko::Error
          false
        end
      end
    end
  end
end
