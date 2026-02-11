# frozen_string_literal: true

require_relative '../../../../../../core/models/toc_entry'

module Shoko
  module Adapters::Output::Ui::Components
    module Sidebar
      # Null object pattern for missing documents.
      class NullDocument
        EMPTY_ARRAY = [].freeze
        EMPTY_HASH = {}.freeze

        def self.wrap(document)
          return document if document

          new
        end

        def toc_entries
          EMPTY_ARRAY
        end

        def chapters
          EMPTY_ARRAY
        end

        def metadata
          EMPTY_HASH
        end

        def title
          nil
        end
      end

      # Builds fallback entries from chapters.
      module FallbackEntriesBuilder
        def self.build(chapters)
          chapters.each_with_index.map do |chapter, idx|
            create_entry(chapter, idx)
          end
        end

        def self.create_entry(chapter, index)
          Core::Models::TOCEntry.new(
            title: chapter.title || "Chapter #{index + 1}",
            href: nil,
            level: 1,
            chapter_index: index,
            navigable: true
          )
        end
      end

      # Extracts entries from document.
      class DocumentEntriesExtractor
        def initialize(document)
          @document = NullDocument.wrap(document)
        end

        def extract
          toc_entries = @document.toc_entries
          return toc_entries unless toc_entries.empty?

          create_fallback_entries
        end

        private

        def create_fallback_entries
          chapters = @document.chapters
          FallbackEntriesBuilder.build(chapters)
        end
      end
    end
  end
end
