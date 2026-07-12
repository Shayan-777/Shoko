# frozen_string_literal: true

module Shoko
  module Adapters
    module BookSources
      module Epub
        # Whether an element hides itself through its own markup, independent of
        # any stylesheet (which the style resolver covers). Shared by the block
        # traversal and the segment builder, and applies to books with no
        # stylesheet at all.
        module MarkupVisibility
          INLINE_HIDDEN_STYLE = /display\s*:\s*none/i

          module_function

          # True when the element hides itself through an inline
          # style="display:none" or the HTML5 boolean `hidden` attribute.
          def markup_hidden?(element)
            return true if INLINE_HIDDEN_STYLE.match?(element.attributes['style'].to_s)

            !element.attributes['hidden'].nil?
          end
        end
      end
    end
  end
end
