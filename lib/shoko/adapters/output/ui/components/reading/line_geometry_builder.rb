# frozen_string_literal: true

require_relative '../../../terminal/text_metrics'
require_relative '../../../rendering/models/line_geometry'
require_relative '../../../../runtime/null_runtime_config'

module Shoko
  module Adapters::Output::Ui::Components
    module Reading
      # Builds `Shoko::Adapters::Output::Rendering::Models::LineGeometry` objects for selection/highlighting.
      class LineGeometryBuilder
        CELL_CACHE_LIMIT = 2_000
        CELL_CACHEABLE_BYTES = 256
        CELL_CACHE_ENABLED_KEY = :shoko_line_geometry_cell_cache_enabled

        class << self
          attr_writer :runtime_config

          def with_cell_cache(enabled:)
            previous = Thread.current[CELL_CACHE_ENABLED_KEY]
            Thread.current[CELL_CACHE_ENABLED_KEY] = enabled ? true : false
            yield
          ensure
            Thread.current[CELL_CACHE_ENABLED_KEY] = previous
          end

          def cell_cache_enabled?
            override = Thread.current[CELL_CACHE_ENABLED_KEY]
            return override unless override.nil?

            !runtime_config.line_geometry_cell_cache_disabled?
          end

          def runtime_config
            @runtime_config || Shoko::Adapters::Runtime::NullRuntimeConfig.instance
          end
        end

        def initialize(runtime_config: nil)
          self.class.runtime_config = runtime_config if runtime_config
          @cell_cache = {}
          @cell_cache_order = []
        end

        def build(page_id:, column_id:, row:, col:, line_offset:, plain_text:, styled_text:)
          plain = plain_text.to_s
          cells = cells_for_plain_text(plain)

          Shoko::Adapters::Output::Rendering::Models::LineGeometry.new(
            page_id: page_id,
            column_id: column_id,
            row: row,
            column_origin: col,
            line_offset: line_offset,
            plain_text: plain,
            styled_text: styled_text,
            cells: cells
          )
        end

        private

        def cells_for_plain_text(plain)
          return build_cells(plain) unless cacheable_plain_text?(plain)
          return build_cells(plain) unless self.class.cell_cache_enabled?

          cached = @cell_cache[plain]
          return cached if cached

          built = build_cells(plain).each(&:freeze).freeze
          store_cached_cells(plain, built)
          built
        end

        def cacheable_plain_text?(plain)
          plain.bytesize <= CELL_CACHEABLE_BYTES
        end

        def store_cached_cells(plain, cells)
          key = plain.frozen? ? plain : plain.dup.freeze
          @cell_cache_order.delete(key)
          @cell_cache_order << key
          @cell_cache[key] = cells
          while @cell_cache_order.length > CELL_CACHE_LIMIT
            oldest = @cell_cache_order.shift
            @cell_cache.delete(oldest)
          end
        end

        def build_cells(plain)
          cell_data = Shoko::Adapters::Output::Terminal::TextMetrics.cell_data_for(plain)
          cell_data.map { |cell| build_cell(cell) }
        end

        def build_cell(cell)
          Shoko::Adapters::Output::Rendering::Models::LineCell.new(
            cluster: cell[:cluster],
            char_start: cell[:char_start],
            char_end: cell[:char_end],
            display_width: cell[:display_width],
            screen_x: cell[:screen_x]
          )
        end
      end
    end
  end
end
