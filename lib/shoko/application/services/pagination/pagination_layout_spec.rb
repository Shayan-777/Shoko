# frozen_string_literal: true

module Shoko
  module Application
    module Services
      module Pagination
        # Normalized pagination layout metadata: the geometry and typesetting
        # attributes that determine wrapped-line layout, plus the runtime and
        # cache keys derived from them.
        PaginationLayoutSpec = Data.define(
          :width,
          :height,
          :view_mode,
          :line_spacing,
          :kitty_images,
          :layout_variant,
          :runtime_key,
          :cache_key
        )
      end
    end
  end
end
