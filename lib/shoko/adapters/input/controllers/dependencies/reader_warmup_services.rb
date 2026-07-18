# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module Dependencies
          # Optional cache/image warmup collaborators handed to the reader boot path.
          ReaderWarmupServices = Data.define(:pagination_cache_preloader, :image_cache_warmup, :kitty_image_renderer)
        end
      end
    end
  end
end
