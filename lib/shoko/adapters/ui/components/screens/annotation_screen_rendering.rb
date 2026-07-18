# frozen_string_literal: true

require 'shoko/shared/terminal/text_sanitizer'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Shared state access for annotation detail and edit screens.
          module AnnotationScreenRendering
            private

            def resolve_book_label
              book_path = menu_state_reader&.selected_annotation_book
              return 'Unknown Book' unless book_path

              raw = File.basename(book_path)
              Shoko::Shared::Terminal::TextSanitizer.sanitize(raw, preserve_newlines: false, preserve_tabs: false)
            end

            attr_reader :menu_state_reader
          end
        end
      end
    end
  end
end
