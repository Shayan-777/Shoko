# frozen_string_literal: true

require_relative 'context_helpers'
require_relative 'absolute_layout'
require 'shoko/application/ports/outbound/formatting/display_line'

module Shoko
  module Application
    module Services
      module Reader
        module Navigation
          # Snaps absolute offsets so image blocks render from their first line.
          # Uses session stores/runtime context - no state-slice ports.
          class ImageOffsetSnapper
            SnapContext = Data.define(:chapter_index, :col_width, :stride, :snapshot)

            def initialize(layout_service:, wrapped_lines_provider:, app_config_store:, reader_session_store:,
                           reader_state_reader:,
                           reader_runtime_context:, logger: nil)
              @layout_service = layout_service
              @wrapped_lines_provider = wrapped_lines_provider
              @app_config_store = app_config_store
              @reader_session_store = reader_session_store
              @reader_runtime_context = reader_runtime_context
              @layout = AbsoluteLayout.new(
                layout_service: layout_service,
                app_config_store: app_config_store,
                reader_session_store: reader_session_store,
                reader_state_reader: reader_state_reader,
                reader_runtime_context: reader_runtime_context,
                logger: logger
              )
              @logger = logger
            end

            def snap(updates, layout_state)
              return updates unless enabled?
              return updates if updates.nil? || updates.empty?

              context = snap_context(updates, layout_state)
              layout_state.view_mode == :split ? snap_split(updates, context) : snap_single(updates, context)
            rescue Shoko::Error => e
              @logger&.debug("image_offset_snapper.snap failed: #{e.message}")
              updates
            end

            private

            def enabled?
              return false unless @layout_service && @wrapped_lines_provider

              @reader_runtime_context.display_capabilities.kitty_images_enabled?(current_config)
            end

            def snap_split(updates, context)
              left = (updates[:left_page] || context.snapshot[:left_page] || 0).to_i
              snapped = snap_offset(context.chapter_index, context.col_width, left, context.stride)
              return updates if snapped == left

              updates[:left_page] = snapped
              updates[:current_page] = snapped
              updates[:right_page] = snapped + context.stride
              updates
            end

            def snap_single(updates, context)
              offset = (updates[:single_page] || context.snapshot[:single_page] || 0).to_i
              snapped = snap_offset(context.chapter_index, context.col_width, offset, context.stride)
              return updates if snapped == offset

              updates[:single_page] = snapped
              updates[:current_page] = snapped
              updates
            end

            def snap_offset(chapter_index, col_width, offset, lines_per_page)
              offset_i = offset.to_i
              return offset_i if offset_i <= 0

              lines = wrapped_lines(chapter_index, col_width, lines_per_page)
              return offset_i unless lines && lines[offset_i]

              image_start_for(lines, offset_i) || offset_i
            rescue Shoko::Error => e
              @logger&.debug("image_offset_snapper.snap_offset failed: #{e.message}")
              offset_i
            end

            def wrapped_lines(chapter_index, col_width, lines_per_page)
              @wrapped_lines_provider.wrapped_lines_for(
                chapter_index: chapter_index,
                col_width: col_width,
                lines_per_page: lines_per_page,
                config_reader: current_config
              )
            end

            def current_config
              @app_config_store.load
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

              meta[:image_render_line] == true
            end

            def image_render(meta)
              return nil unless meta

              render = meta[:image_render]
              render.is_a?(Hash) ? render : nil
            end

            def line_metadata(line)
              return nil unless line.is_a?(Shoko::Application::Ports::Outbound::Formatting::DisplayLine)

              meta = line.metadata
              normalize_meta_hash(meta)
            end

            def image_src(meta)
              image = meta[:image]
              return nil unless image.is_a?(Hash)

              image[:src]
            end

            def normalize_meta_hash(value)
              return nil unless value.is_a?(Hash)

              value.each_with_object({}) do |(key, raw), acc|
                normalized_key = key.is_a?(String) ? key.to_sym : key
                acc[normalized_key] = normalize_meta_value(raw)
              end
            end

            def normalize_meta_value(value)
              if value.is_a?(Hash)
                return value.transform_keys { |key| key.is_a?(String) ? key.to_sym : key }
              end

              value
            end

            def snap_context(updates, layout_state)
              snapshot = layout_state.snapshot
              SnapContext.new(
                chapter_index: updates[:current_chapter] || ContextHelpers.current_chapter(snapshot),
                col_width: @layout.column_width(snapshot, layout_state.view_mode),
                stride: layout_state.stride,
                snapshot: snapshot
              )
            end
          end
        end
      end
    end
  end
end
