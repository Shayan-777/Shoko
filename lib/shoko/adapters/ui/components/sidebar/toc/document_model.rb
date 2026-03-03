# frozen_string_literal: true

require_relative '../../../../../core/ports/outbound/reader_document'

module Shoko
  module Adapters
    module Ui
      module Components
        module Sidebar
          # Null object pattern for missing documents.
          class NullDocument
            include Shoko::Core::Ports::Outbound::ReaderDocument

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

            def chapter_count
              0
            end

            def get_chapter(_index)
              nil
            end

            def canonical_path
              nil
            end

            def cached?
              false
            end
          end
        end
      end
    end
  end
end
