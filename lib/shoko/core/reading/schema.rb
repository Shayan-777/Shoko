# frozen_string_literal: true

module Shoko
  module Core
    module Reading
      # Domain-owned reading-state schema fragment.
      #
      # Declares the field set and defaults for the portion of the runtime state
      # that represents reading-domain truths: which book is open, where the
      # reader is positioned in it, what is selected, what is bookmarked or
      # annotated. These would exist for any UI of this reader.
      #
      # The composition root registers this fragment with the
      # `Application::State::SchemaRegistry` to compose the initial runtime state.
      module Schema
        PARTITION = :reader

        FIELDS = %i[
          book_path
          current_chapter
          current_page
          current_page_index
          single_page
          left_page
          right_page
          selection
          bookmarks
          annotations
        ].freeze

        DEFAULTS = {
          book_path: nil,
          current_chapter: 0,
          current_page: 0,
          current_page_index: 0,
          single_page: 0,
          left_page: 0,
          right_page: 0,
          selection: nil,
          bookmarks: [],
          annotations: [],
        }.freeze

        module_function

        def contribute(_context = {})
          { PARTITION => DEFAULTS.dup }
        end
      end
    end
  end
end
