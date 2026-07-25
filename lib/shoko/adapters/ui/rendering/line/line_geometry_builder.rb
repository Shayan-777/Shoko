# frozen_string_literal: true

require 'shoko/shared/thread_local_scope'
require 'shoko/shared/terminal/text_metrics'
require_relative '../models/line_cell'
require_relative '../models/line_geometry'
require 'shoko/application/ports/outbound/runtime_config'

module Shoko
  module Adapters
    module Ui
      module Components
        module Reading
          # Builds `Shoko::Adapters::Ui::Rendering::Models::LineGeometry` objects for selection/highlighting.
          class LineGeometryBuilder
            CELL_CACHE_LIMIT = 2_000
            CELL_CACHEABLE_BYTES = 256
            CELL_CACHE_ENABLED_KEY = :shoko_line_geometry_cell_cache_enabled
            RUNTIME_CONFIG_KEY = :shoko_line_geometry_runtime_config

            class << self
              def with_runtime_config(config:, &)
                Shoko::Shared::ThreadLocalScope.with(key: RUNTIME_CONFIG_KEY, value: config, &)
              end

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
                config = Thread.current[RUNTIME_CONFIG_KEY]
                return config if config

                raise Shoko::ConfigurationError, 'LineGeometryBuilder runtime_config is not configured'
              end
            end

            def initialize(runtime_config:)
              unless runtime_config.is_a?(Shoko::Application::Ports::Outbound::RuntimeConfig)
                raise ArgumentError, 'runtime_config must implement Application::Ports::Outbound::RuntimeConfig'
              end

              @runtime_config = runtime_config
              @cell_cache = {}
              @cell_cache_order = []
            end

            def build(page_id:, column_id:, row:, col:, line_offset:, plain_text:, styled_text:)
              with_runtime_config do
                plain = plain_text.to_s
                cells = cells_for_plain_text(plain)

                Shoko::Adapters::Ui::Rendering::Models::LineGeometry.new(
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
            end

            private

            def with_runtime_config(&)
              return yield unless @runtime_config

              self.class.with_runtime_config(config: @runtime_config, &)
            end

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
              cell_data = Shoko::Shared::Terminal::TextMetrics.cell_data_for(plain)
              cell_data.map { |cell| build_cell(cell) }
            end

            def build_cell(cell)
              Shoko::Adapters::Ui::Rendering::Models::LineCell.new(
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
  end
end
