# frozen_string_literal: true

require_relative 'epub/epub_importer'

module Shoko
  module Adapters::BookSources
    # Backward-compatible alias so existing code referencing
    # Shoko::Adapters::BookSources::EpubImporter continues to work.
    EpubImporter = Epub::EpubImporter
  end
end
