# frozen_string_literal: true

require_relative '../../adapters/book_sources/format_registry'

module Shoko
  module Adapters
    module BookSources
      # Adapter-side probe for filesystem book eligibility checks.
      class BookFileProbe
        def initialize(format_registry: Shoko::Adapters::BookSources::FormatRegistry)
          @format_registry = format_registry
        end

        def book_file?(path)
          @format_registry.supported_extension?(path) &&
            File.readable?(path) &&
            File.size(path).positive?
        end
      end
    end
  end
end
