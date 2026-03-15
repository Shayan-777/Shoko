# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module Reader
          module InlineLink
            # Resolves whether a pointer event lands on an inline-link span.
            class LinkHitResolver
              def initialize(coordinate_service:, rendered_content_reader:)
                @coordinate_service = coordinate_service
                @rendered_content_reader = rendered_content_reader
              end

              def context_for_event(event)
                rendered = rendered_lines
                return nil unless rendered

                anchor = anchor_for_event(event, rendered)
                return nil unless anchor

                entry = rendered[anchor.geometry_key]
                geometry = entry && entry[:geometry]
                return nil unless geometry
                return nil unless point_within_geometry?(event, geometry)

                span = link_span_for_anchor(entry, geometry, anchor.cell_index)
                return nil unless span

                href = value_for(span, :href).to_s.strip
                return nil if href.empty?

                { href: href, entry: entry, geometry: geometry, span: span }
              end

              def hit_for_event(event)
                context = context_for_event(event)
                return nil unless context

                span = context.fetch(:span)
                geometry = context.fetch(:geometry)
                entry = context.fetch(:entry)
                {
                  href: context.fetch(:href),
                  line_offset: geometry.line_offset.to_i,
                  start_char: value_for(span, :start_char).to_i,
                  end_char: value_for(span, :end_char).to_i,
                  chapter_source_path: value_for(entry, :chapter_source_path)
                }
              end

              private

              def rendered_lines
                rendered = @rendered_content_reader&.rendered_lines
                return nil unless rendered.is_a?(Hash) && !rendered.empty?

                rendered
              end

              def anchor_for_event(event, rendered)
                point = { x: event[:x], y: event[:y] }
                @coordinate_service.anchor_from_point(point, rendered, bias: :nearest)
              end

              def point_within_geometry?(event, geometry)
                row = event[:y].to_i + 1
                return false unless row == geometry.row.to_i

                width = geometry.visible_width.to_i
                return false if width <= 0

                col = event[:x].to_i + 1
                start_col = geometry.column_origin.to_i
                end_col = start_col + width - 1
                col.between?(start_col, end_col)
              end

              def link_span_for_anchor(entry, geometry, cell_index)
                spans = Array(value_for(entry, :link_spans))
                return nil if spans.empty? || geometry.nil?

                cells = Array(geometry.cells)
                index = cell_index.to_i
                return nil if index.negative? || index >= cells.length

                char_index = cells[index].char_start.to_i
                link_span_for_char(spans, char_index)
              end

              def link_span_for_char(spans, char_index)
                spans.find do |candidate|
                  start_char = value_for(candidate, :start_char).to_i
                  end_char = value_for(candidate, :end_char).to_i
                  char_index >= start_char && char_index < end_char
                end
              end

              def value_for(source, key)
                return nil unless source

                normalized = source.each_with_object({}) do |(entry_key, value), result|
                  result[entry_key.is_a?(String) ? entry_key.to_sym : entry_key] = value
                end
                normalized[key]
              end
            end
          end
        end
      end
    end
  end
end
