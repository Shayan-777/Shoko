# frozen_string_literal: true

require_relative 'context_helpers'
require_relative 'absolute_layout'

module Shoko
  module Core
    module Services
      module Navigation
        # Snaps absolute offsets so image blocks render from their first line.
        # Uses hexagonal ports for reading state - no direct state_store access.
        class ImageOffsetSnapper
          # Simple bridge to provide .get() interface from config_reader for backward compatibility
          # with formatting_service until it's refactored to use ports directly.
          class ConfigBridge
            def initialize(config_reader)
              @config_reader = config_reader
            end

            def get(path)
              case path
              when %i[config kitty_images]
                @config_reader.kitty_images
              when %i[config view_mode]
                @config_reader.view_mode
              when %i[config line_spacing]
                @config_reader.line_spacing
              end
            end
          end

          # @param layout_service [Object] Layout service
          # @param formatting_service [Object, nil] Formatting service
          # @param document [Object, nil] Document
          # @param display_capabilities [Core::Ports::DisplayCapabilities] Display capability adapter (required)
          # @param config_reader [Core::Ports::ConfigReader] Port for reading config
          # @param reader_state_reader [Core::Ports::ReaderStateReader] Port for reading reader state
          # @param ui_state_reader [Core::Ports::UIStateReader] Port for reading UI state
          def initialize(layout_service:, formatting_service:, document:, display_capabilities:,
                         config_reader:, reader_state_reader:, ui_state_reader:)
            @layout_service = layout_service
            @formatting_service = formatting_service
            @document = document
            @config_reader = config_reader
            @reader_state_reader = reader_state_reader
            @ui_state_reader = ui_state_reader
            @layout = AbsoluteLayout.new(
              layout_service: layout_service,
              config_reader: config_reader,
              reader_state_reader: reader_state_reader,
              ui_state_reader: ui_state_reader
            )
            @display_capabilities = display_capabilities
            @config_bridge = ConfigBridge.new(config_reader)
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

            @display_capabilities.kitty_images_enabled?(@config_bridge)
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
              config: @config_bridge,
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
