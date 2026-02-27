# frozen_string_literal: true

require_relative 'nav_context'

module Shoko
  module Application
    module Services
      module Reader
        module Navigation
          # Computes absolute-mode navigation offsets for single and split view.
          # Returns hashes describing desired state field updates; facade applies.
          module AbsoluteStrategy
            module_function

            def next_page(context)
              if context.view_mode == :split
                next_page_split(context)
              else
                next_page_single(context)
              end
            end

            def prev_page(context)
              if context.view_mode == :split
                prev_page_split(context)
              else
                prev_page_single(context)
              end
            end

            def scroll(context, direction, lines)
              lines = lines.to_i
              return {} if lines <= 0

              if context.view_mode == :split
                scroll_split(context, direction, lines)
              else
                scroll_single(context, direction, lines)
              end
            end

            def go_to_start(context)
              if context.view_mode == :split
                stride = split_stride(context)
                { current_chapter: 0, current_page: 0, single_page: 0, left_page: 0, right_page: stride }
              else
                { current_chapter: 0, current_page: 0, single_page: 0, left_page: 0, right_page: split_stride(context) }
              end
            end

            def go_to_end(context)
              # Facade will compute last_page for last chapter; provide intent only.
              last_chapter = [context.total_chapters - 1, 0].max
              { current_chapter: last_chapter, align_to_last: true }
            end

            def jump_to_chapter(context, index)
              if context.view_mode == :split
                stride = split_stride(context)
                { current_chapter: index, current_page: 0, single_page: 0, left_page: 0, right_page: stride }
              else
                { current_chapter: index, current_page: 0, single_page: 0, left_page: 0,
                  right_page: split_stride(context) }
              end
            end

            # --- helpers ---
            def next_page_single(context)
              stride = single_stride(context)
              cur = context.single_page.to_i
              max_offset = max_offset(context)

              if cur < max_offset
                new_offset = [cur + stride, max_offset].min
                { single_page: new_offset, current_page: new_offset }
              elsif context.current_chapter < context.total_chapters - 1
                { advance_chapter: :next }
              else
                {}
              end
            end

            def prev_page_single(context)
              stride = single_stride(context)
              cur = context.single_page.to_i
              if cur.positive?
                new_offset = [cur - stride, 0].max
                { single_page: new_offset, current_page: new_offset }
              elsif context.current_chapter.positive?
                { advance_chapter: :prev, stride: stride }
              else
                {}
              end
            end

            def next_page_split(context)
              stride = split_stride(context)
              left = context.left_page.to_i
              max_offset = max_offset(context)

              if left < max_offset
                new_left = [left + stride, max_offset].min
                { left_page: new_left, right_page: new_left + stride, current_page: new_left }
              elsif context.current_chapter < context.total_chapters - 1
                { advance_chapter: :next }
              else
                {}
              end
            end

            def prev_page_split(context)
              stride = split_stride(context)
              left = context.left_page.to_i
              if left.positive?
                new_left = [left - stride, 0].max
                { left_page: new_left, right_page: new_left + stride, current_page: new_left }
              elsif context.current_chapter.positive?
                { advance_chapter: :prev, stride: stride }
              else
                {}
              end
            end

            def scroll_single(context, direction, lines)
              cur = context.single_page.to_i
              max_offset = max_offset(context)
              new_offset = case direction
                           when :up
                             [cur - lines, 0].max
                           when :down
                             [cur + lines, max_offset].min
                           else
                             raise ArgumentError, "Invalid scroll direction: #{direction}"
                           end

              return {} if new_offset == cur

              { single_page: new_offset, current_page: new_offset }
            end

            def scroll_split(context, direction, lines)
              cur = context.left_page.to_i
              stride = split_stride(context)
              max_offset = max_offset(context)
              new_offset = case direction
                           when :up
                             [cur - lines, 0].max
                           when :down
                             [cur + lines, max_offset].min
                           else
                             raise ArgumentError, "Invalid scroll direction: #{direction}"
                           end

              return {} if new_offset == cur

              { left_page: new_offset, right_page: new_offset + stride, current_page: new_offset }
            end

            def single_stride(context)
              stride = context.lines_per_page.to_i
              stride = context.column_lines_per_page.to_i if stride <= 0
              stride = 1 if stride <= 0
              stride
            end

            def split_stride(context)
              stride = context.column_lines_per_page.to_i
              stride = context.lines_per_page.to_i if stride <= 0
              stride = 1 if stride <= 0
              stride
            end

            def max_offset(context)
              context.max_offset_in_chapter.to_i
            end
          end
        end
      end
    end
  end
end
