# frozen_string_literal: true

require_relative 'context_helpers'
require_relative 'absolute_layout'
require_relative '../../../adapters/output/kitty/kitty_graphics'

module Shoko
  module Core
    module Services
      module Navigation
        # Snaps absolute offsets so image blocks render from their first line.
        class ImageOffsetSnapper
          def initialize(state_store:, layout_service:, formatting_service:, document:)
            @state_store = state_store
            @layout_service = layout_service
            @formatting_service = formatting_service
            @document = document
            @layout = AbsoluteLayout.new(state_store: state_store, layout_service: layout_service)
          end

          def snap(updates, layout_state)
            return updates unless enabled?
            return updates if updates.nil? || updates.empty?

            snapshot = layout_state.snapshot
            view_mode = layout_state.view_mode
            stride = layout_state.stride
            chapter_index = updates[%i[reader current_chapter]] || ContextHelpers.current_chapter(snapshot)
            col_width = @layout.column_width(snapshot, view_mode)

            if view_mode == :split
              snap_split(updates, chapter_index, col_width, stride, snapshot)
            else
              snap_single(updates, chapter_index, col_width, stride, snapshot)
            end
          rescue StandardError
            updates
          end

          private

          def enabled?
            return false unless @layout_service && @formatting_service && @document

            Shoko::Adapters::Output::Kitty::KittyGraphics.enabled_for?(@state_store)
          end

          def snap_split(updates, chapter_index, col_width, stride, snapshot)
            left = (updates[%i[reader left_page]] || snapshot.dig(:reader, :left_page) || 0).to_i
            snapped = snap_offset(chapter_index, col_width, left, stride)
            return updates if snapped == left

            updates[%i[reader left_page]] = snapped
            updates[%i[reader current_page]] = snapped
            updates[%i[reader right_page]] = snapped + stride
            updates
          end

          def snap_single(updates, chapter_index, col_width, stride, snapshot)
            offset = (updates[%i[reader single_page]] || snapshot.dig(:reader, :single_page) || 0).to_i
            snapped = snap_offset(chapter_index, col_width, offset, stride)
            return updates if snapped == offset

            updates[%i[reader single_page]] = snapped
            updates[%i[reader current_page]] = snapped
            updates
          end

          def snap_offset(chapter_index, col_width, offset, lines_per_page)
            offset_i = offset.to_i
            return offset_i if offset_i <= 0

            lines = wrapped_lines(chapter_index, col_width, lines_per_page)
            return offset_i unless lines && lines[offset_i]

            image_start_for(lines, offset_i) || offset_i
          rescue StandardError
            offset_i
          end

          def wrapped_lines(chapter_index, col_width, lines_per_page)
            @formatting_service.wrap_all(
              @document,
              chapter_index,
              col_width,
              config: @state_store,
              lines_per_page: lines_per_page
            )
          end

          def image_start_for(lines, offset)
            meta = line_metadata(lines[offset])
            render = image_render(meta)
            return nil unless render

            src = image_src(meta)
            return nil if src.to_s.empty?
            return offset if render_line?(meta)

            idx = offset
            while idx.positive?
              cur_meta = line_metadata(lines[idx])
              break unless same_image?(cur_meta, src)
              return idx if render_line?(cur_meta)

              idx -= 1
            end

            0
          end

          def same_image?(meta, src)
            return false unless image_render(meta)

            image_src(meta).to_s == src.to_s
          end

          def render_line?(meta)
            return false unless meta

            meta.key?(:image_render_line) ? meta[:image_render_line] == true : meta['image_render_line'] == true
          end

          def image_render(meta)
            return nil unless meta

            render = meta[:image_render] || meta['image_render']
            render.is_a?(Hash) ? render : nil
          end

          def line_metadata(line)
            return nil unless line.respond_to?(:metadata)

            meta = line.metadata
            meta.is_a?(Hash) ? meta : nil
          rescue StandardError
            nil
          end

          def image_src(meta)
            image = meta[:image] || meta['image'] || {}
            image[:src] || image['src']
          rescue StandardError
            nil
          end
        end
      end
    end
  end
end
