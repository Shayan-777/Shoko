# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module Components
        module Sidebar
          # Precomputes line offsets for variable-height entries.
          class LineIndex
            attr_reader :total_height

            def initialize(entries, max_width, wrap_cache, text_metrics)
              @offsets = []
              @heights = []
              total = 0

              entries.each do |entry|
                @offsets << total
                height = EntryLayoutHelper.line_count(entry, max_width, wrap_cache, text_metrics)
                @heights << height
                total += height
              end

              @total_height = total
            end

            def height_for(index)
              @heights[index] || 0
            end

            def offset_for(index)
              @offsets[index] || 0
            end

            def entry_index_for_line(line)
              return nil if @offsets.empty?
              return 0 if @total_height <= 0

              line = line.to_i
              line = 0 if line.negative?
              line = @total_height - 1 if line >= @total_height

              low = 0
              high = @offsets.length - 1
              while low <= high
                mid = (low + high) / 2
                if @offsets[mid] <= line
                  return mid if mid == @offsets.length - 1 || @offsets[mid + 1] > line

                  low = mid + 1
                else
                  high = mid - 1
                end
              end

              0
            end
          end
        end
      end
    end
  end
end
