# frozen_string_literal: true

module Shoko
  module Presentation::Ui::Components
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
    end
  end
end
