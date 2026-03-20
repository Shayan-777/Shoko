# frozen_string_literal: true

module Shoko
  module Adapters
    module Output
      module Formatting
        class FormattingService
          class LineAssembler
            class TableRenderer
              # Computes table border junctions and emits boundary display lines.
              module BoundaryRenderingSupport
                private

                def build_row_vertical_borders(grid, row_count, col_count)
                  Array.new(row_count) do |row_index|
                    borders = Array.new(col_count + 1, true)
                    borders[0] = true
                    borders[col_count] = true
                    (1...col_count).each do |col|
                      borders[col] = grid[row_index][col - 1] != grid[row_index][col]
                    end
                    borders
                  end
                end

                def boundary_line(boundary_index, context)
                  horizontal = horizontal_segments(
                    boundary_index,
                    context[:grid],
                    context[:row_count],
                    context[:col_count]
                  )
                  upward = boundary_borders(boundary_index, context[:row_v_borders], context[:col_count])
                  downward = boundary_borders(boundary_index + 1, context[:row_v_borders], context[:col_count])

                  build_boundary_display_line(context, horizontal, upward, downward)
                end

                def build_boundary_display_line(context, horizontal_segments, upward_borders, downward_borders)
                  text = +''
                  segments = []
                  buffers = { segments: segments, text: text }
                  borders = { up: upward_borders, down: downward_borders }
                  append_boundary_columns(context, horizontal_segments, borders, buffers)
                  build_display_line(text, segments, context[:metadata])
                end

                def append_boundary_column(segments:, text:, col:, col_count:, h_segments:, up_borders:, down_borders:,
                                           segment_widths:)
                  append_boundary_junction(
                    segments: segments,
                    text: text,
                    col: col,
                    col_count: col_count,
                    h_segments: h_segments,
                    up_borders: up_borders,
                    down_borders: down_borders
                  )
                  return if col == col_count

                  append_boundary_segment(segments, text, h_segments[col], segment_widths[col])
                end

                def append_boundary_junction(
                  segments:,
                  text:,
                  col:,
                  col_count:,
                  h_segments:,
                  up_borders:,
                  down_borders:
                )
                  leftward = col.positive? ? h_segments[col - 1] : false
                  rightward = col < col_count ? h_segments[col] : false
                  char = junction_char(
                    upward: up_borders[col],
                    downward: down_borders[col],
                    leftward: leftward,
                    rightward: rightward
                  )
                  append_segment(segments, text, char, {})
                end

                def append_boundary_segment(segments, text, has_boundary, width)
                  segment_char = has_boundary ? '─' : ' '
                  append_segment(segments, text, segment_char * width, {})
                end

                def append_boundary_columns(context, horizontal_segments, borders, buffers)
                  (0..context[:col_count]).each do |col|
                    append_boundary_column(
                      segments: buffers[:segments],
                      text: buffers[:text],
                      col: col,
                      col_count: context[:col_count],
                      h_segments: horizontal_segments,
                      up_borders: borders[:up],
                      down_borders: borders[:down],
                      segment_widths: context[:segment_widths]
                    )
                  end
                end

                def build_display_line(text, segments, metadata)
                  Shoko::Core::Models::DisplayLine.new(text: text, segments: segments, metadata: metadata)
                end

                def boundary_borders(index, row_v_borders, col_count)
                  return Array.new(col_count + 1, false) if index.negative? || index >= row_v_borders.length

                  row_v_borders[index]
                end

                def horizontal_segments(boundary_index, grid, row_count, col_count)
                  return Array.new(col_count, true) if boundary_index.negative? || boundary_index >= row_count - 1

                  Array.new(col_count) { |col| grid[boundary_index][col] != grid[boundary_index + 1][col] }
                end

                def junction_char(upward:, downward:, leftward:, rightward:)
                  mask = 0
                  mask |= 8 if upward
                  mask |= 4 if downward
                  mask |= 2 if leftward
                  mask |= 1 if rightward

                  JUNCTION_CHARS.fetch(mask, ' ')
                end

                def append_segment(segments, text, value, styles)
                  return if value.to_s.empty?

                  text << value
                  if segments.empty? || segments.last.styles != styles
                    segments << Shoko::Core::Models::TextSegment.new(text: value, styles: styles)
                  else
                    previous = segments[-1]
                    segments[-1] = Shoko::Core::Models::TextSegment.new(text: previous.text + value, styles: styles)
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end
