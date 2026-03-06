# frozen_string_literal: true

require_relative '../../../../core/ports/outbound/runtime_config'
require_relative '../../../../core/models/content_block'

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

            def record(geometry, line: nil)
              return unless @buffer.is_a?(Hash)
              return if skip_geometry?(geometry)

              width = geometry.visible_width
              @buffer[geometry.key] = entry_for(geometry, width, line)

              dump_geometry(geometry) if geometry_debug_enabled?
            end

            private

            def skip_geometry?(geometry)
              width = geometry.visible_width
              width <= 0 && geometry.plain_text.to_s.empty?
            end

            def entry_for(geometry, width, line)
              end_col = geometry.column_origin + width - 1
              link_spans = link_spans_for(line, geometry.plain_text.length)
              {
                row: geometry.row,
                col: geometry.column_origin,
                col_end: end_col,
                text: geometry.plain_text,
                width: width,
                geometry: geometry,
                link_spans: link_spans,
                chapter_source_path: chapter_source_path_for(line),
              }
            end

            def link_spans_for(line, max_chars)
              return [] unless line.is_a?(Shoko::Core::Models::DisplayLine)

              spans = []
              cursor = 0
              limit = max_chars.to_i
              Array(line.segments).each do |segment|
                text = segment&.text.to_s
                segment_length = text.length
                next if segment_length <= 0

                href = segment_link_href(segment)
                if href
                  start_char = cursor
                  end_char = [cursor + segment_length, limit].min
                  if start_char < limit && start_char < end_char
                    spans << { start_char: start_char, end_char: end_char, href: href }
                  end
                end

                cursor += segment_length
                break if cursor >= limit
              end

              spans
            end

            def segment_link_href(segment)
              styles = segment&.styles
              return nil unless styles.is_a?(Hash)

              href = styles[:link] || styles['link']
              return nil if href.nil?

              href_text = href.to_s.strip
              href_text.empty? ? nil : href_text
            end

            def chapter_source_path_for(line)
              return nil unless line.is_a?(Shoko::Core::Models::DisplayLine)

              metadata = line.metadata || {}
              metadata[:chapter_source_path] || metadata['chapter_source_path']
            end

            def geometry_debug_enabled?
              runtime_config = @dependencies&.runtime_config
              unless runtime_config.is_a?(Shoko::Core::Ports::Outbound::RuntimeConfig)
                raise ArgumentError, 'reader rendering dependencies must provide runtime_config'
              end

              runtime_config&.debug_geometry_enabled? == true
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
