# frozen_string_literal: true

require_relative '../../../../shared/runtime/null_runtime_config'

module Shoko
  module Adapters
    module Ui
      module Components
        module Reading
          # Records per-line geometry into the state buffer so selection/overlays can
          # use the exact rendered layout.
          class RenderedLinesRecorder
            def initialize(buffer:, dependencies:)
              @buffer = buffer
              @dependencies = dependencies
            end

            def record(geometry)
              return unless @buffer.is_a?(Hash)
              return if skip_geometry?(geometry)

              width = geometry.visible_width
              @buffer[geometry.key] = entry_for(geometry, width)

              dump_geometry(geometry) if geometry_debug_enabled?
            end

            private

            def skip_geometry?(geometry)
              width = geometry.visible_width
              width <= 0 && geometry.plain_text.to_s.empty?
            end

            def entry_for(geometry, width)
              end_col = geometry.column_origin + width - 1
              {
                row: geometry.row,
                col: geometry.column_origin,
                col_end: end_col,
                text: geometry.plain_text,
                width: width,
                geometry: geometry,
              }
            end

            def geometry_debug_enabled?
              runtime_config = @dependencies&.runtime_config || Shoko::Shared::Runtime::NullRuntimeConfig.instance
              runtime_config&.debug_geometry_enabled? == true
            rescue StandardError
              false
            end

            def dump_geometry(geometry)
              payload = geometry.to_h
              logger = resolve_logger
              return logger.debug('geometry.line', payload) if logger

              warn("[geometry] #{payload}")
            end

            def resolve_logger
              @dependencies&.logger
            end
          end
        end
      end
    end
  end
end
