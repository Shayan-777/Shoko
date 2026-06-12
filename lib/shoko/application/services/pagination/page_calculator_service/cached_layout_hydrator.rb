# frozen_string_literal: true

module Shoko
  module Application
    module Services
      module Pagination
        # Restores compact cached pages into the active in-memory dynamic layout state.
        class CachedLayoutHydrator
          def initialize(dynamic_layout_cache:, restore_mapping:, config_reader:, layout_resolver:)
            @dynamic_layout_cache = dynamic_layout_cache
            @restore_mapping = restore_mapping
            @config_reader = config_reader
            @layout_resolver = layout_resolver
          end

          def hydrate(pages, width:, height:)
            @dynamic_layout_cache.load_pages(
              pages: pages,
              key: cached_layout_key(width:, height:),
              width: width,
              height: height
            )
            @restore_mapping.rebuild!(@dynamic_layout_cache.pages_data)
          end

          private

          def cached_layout_key(width:, height:)
            return nil unless width && height

            @layout_resolver.runtime_key(
              config_reader: @config_reader,
              width: width,
              height: height
            )
          end
        end
      end
    end
  end
end
