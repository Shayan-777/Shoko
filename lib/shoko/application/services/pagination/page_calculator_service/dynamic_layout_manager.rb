# frozen_string_literal: true

module Shoko
  module Application
    module Services
      module Pagination
        # Owns in-memory dynamic layout activation.
        class DynamicLayoutManager
          def initialize(dynamic_layout_cache:, restore_mapping:, config_reader:, layout_resolver:,
                         dynamic_page_builder:, logger: nil)
            @dynamic_layout_cache = dynamic_layout_cache
            @restore_mapping = restore_mapping
            @config_reader = config_reader
            @layout_resolver = layout_resolver
            @dynamic_page_builder = dynamic_page_builder
            @logger = logger
          end

          def build_map(width:, height:, doc:, &on_progress)
            pages = build_pages(width: width, height: height, doc: doc, progress: on_progress)
            activate_layout(pages:, width: width, height: height)
            build_map_payload(width:, height:)
          end

          private

          def activate_layout(pages:, width:, height:)
            @dynamic_layout_cache.activate(
              key: runtime_layout_key(width:, height:),
              pages: pages,
              width: width,
              height: height
            )
            @restore_mapping.rebuild!(@dynamic_layout_cache.pages_data)
          end

          def build_map_payload(width:, height:)
            {
              pages: @dynamic_layout_cache.pages_data,
              total_pages: @dynamic_layout_cache.total_pages,
              last_width: width,
              last_height: height,
            }
          end

          def build_pages(width:, height:, doc:, progress:)
            @dynamic_page_builder.call(
              width: width,
              height: height,
              doc: doc,
              progress: progress
            )
          end

          def runtime_layout_key(width:, height:)
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
