# frozen_string_literal: true

module Shoko
  module Application
    module Services
      module Pagination
        # Owns in-memory dynamic layout activation, switching, and sidebar precomputation.
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

          def build_map(width:, height:, doc:, sidebar_visible:, &on_progress)
            visibility = sidebar_visible?(sidebar_visible)
            pages = build_pages(
              width: width,
              height: height,
              doc: doc,
              sidebar_visible: visibility,
              progress: on_progress
            )
            finalize_build(pages:, width: width, height: height, doc: doc, visibility: visibility)
          end

          def switch_layout(width:, height:, doc:, sidebar_visible:, reader_state_reader:)
            return { status: :pass } unless @config_reader.page_numbering_mode == :dynamic
            return { status: :missing } unless doc

            build_switch_payload(
              width: width,
              height: height,
              doc: doc,
              visibility: sidebar_visible?(sidebar_visible),
              reader_state_reader: reader_state_reader
            )
          rescue Shoko::Error => e
            @logger&.debug('switch_dynamic_layout_variant failed', error: e.message)
            { status: :error }
          end

          private

          def dynamic_layout_pages_for(width:, height:, doc:, sidebar_visible:)
            key = runtime_layout_key(width:, height:, sidebar_visible:)
            pages = @dynamic_layout_cache.cached_pages(key)
            return pages if pages

            pages = build_pages(width: width, height: height, doc: doc, sidebar_visible: sidebar_visible, progress: nil)
            @dynamic_layout_cache.cache_pages(key: key, pages: pages)
            pages
          end

          def activate_layout(pages:, width:, height:, sidebar_visible:)
            @dynamic_layout_cache.activate(
              key: runtime_layout_key(width:, height:, sidebar_visible: sidebar_visible),
              pages: pages,
              width: width,
              height: height,
              sidebar_visible: sidebar_visible
            )
            @restore_mapping.rebuild!(@dynamic_layout_cache.pages_data)
          end

          def finalize_build(pages:, width:, height:, doc:, visibility:)
            activate_layout(pages:, width: width, height: height, sidebar_visible: visibility)
            precompute_sidebar_variant(width:, height:, doc:, active_sidebar_visible: visibility)
            build_map_payload(width:, height:)
          end

          def build_map_payload(width:, height:)
            {
              pages: @dynamic_layout_cache.pages_data,
              total_pages: @dynamic_layout_cache.total_pages,
              last_width: width,
              last_height: height,
            }
          end

          def build_switch_payload(width:, height:, doc:, visibility:, reader_state_reader:)
            position = current_dynamic_position(reader_state_reader)
            pages = dynamic_layout_pages_for(width:, height:, doc:, sidebar_visible: visibility)
            activate_layout(pages:, width: width, height: height, sidebar_visible: visibility)
            precompute_sidebar_variant(width:, height:, doc:, active_sidebar_visible: visibility)
            switched_payload(width:, height:, position:)
          end

          def switched_payload(width:, height:, position:)
            {
              status: :switched,
              current_page_index: @restore_mapping.find_page_index(
                position[:chapter_index].to_i,
                position[:line_offset]
              ),
              total_pages: @dynamic_layout_cache.total_pages,
              last_width: width,
              last_height: height,
            }
          end

          def precompute_sidebar_variant(width:, height:, doc:, active_sidebar_visible:)
            return unless @config_reader.view_mode == :single

            alternate = !active_sidebar_visible
            key = runtime_layout_key(width:, height:, sidebar_visible: alternate)
            return if @dynamic_layout_cache.cached?(key)

            pages = build_pages(width: width, height: height, doc: doc, sidebar_visible: alternate, progress: nil)
            @dynamic_layout_cache.cache_pages(key: key, pages: pages)
          rescue Shoko::Error => e
            @logger&.debug('precompute_sidebar_variant failed', error: e.message)
          end

          def build_pages(width:, height:, doc:, sidebar_visible:, progress:)
            @dynamic_page_builder.call(
              width: width,
              height: height,
              doc: doc,
              sidebar_visible: sidebar_visible,
              progress: progress
            )
          end

          def runtime_layout_key(width:, height:, sidebar_visible:)
            @layout_resolver.runtime_key(
              config_reader: @config_reader,
              width: width,
              height: height,
              sidebar_visible: sidebar_visible
            )
          end

          def sidebar_visible?(value)
            value == true
          end

          def current_dynamic_position(reader_state_reader)
            current_page = @dynamic_layout_cache.raw_page(reader_state_reader.current_page_index.to_i)
            chapter_index = if current_page.is_a?(Hash)
                              current_page[:chapter_index] || reader_state_reader.current_chapter
                            else
                              reader_state_reader.current_chapter
                            end

            {
              chapter_index: chapter_index,
              line_offset: current_page.is_a?(Hash) ? current_page[:start_line].to_i : 0,
            }
          end
        end
      end
    end
  end
end
