# frozen_string_literal: true

require 'digest/sha1'

require_relative '../../../../../core/models/content_block'

module Shoko
  module Adapters::Output::Formatting
    class FormattingService
      class LineAssembler
        # Builds display lines and metadata for block-level and inline images.
        class ImageBuilder
          include Shoko::Core::Models

          MAX_ID = 4_294_967_295
          RENDERABLE_IMAGE_EXTENSIONS = %w[.png .jpg .jpeg].freeze

          def initialize(width:, chapter_index:, chapter_source_path:, max_image_rows: nil)
            @width = width.to_i
            @chapter_index = chapter_index
            @chapter_source_path = chapter_source_path
            @max_image_rows = normalized_max_image_rows(max_image_rows)
            @inline_image_counter = 0
          end

          def block_lines(block, block_index:, base_metadata:)
            render = base_metadata.merge(image_render: block_render_metadata(block, block_index))
            image_lines(render, rows: render.dig(:image_render, :rows).to_i)
          end

          def inline_lines(inline, indent_cols)
            @inline_image_counter += 1
            cols_available = [@width - indent_cols.to_i, 1].max
            render = inline_metadata(inline, cols_available, indent_cols.to_i, @inline_image_counter)
            image_lines(render, rows: render.dig(:image_render, :rows).to_i)
          end

          def renderable_block_image?(block)
            image = (block.metadata || {})[:image] || (block.metadata || {})['image'] || {}
            src = image[:src] || image['src']
            renderable_image_src?(src)
          rescue StandardError
            false
          end

          def renderable_image_src?(src)
            return false if src.nil? || src.to_s.empty?

            ext = File.extname(src.to_s.split(/[?#]/, 2).first.to_s).downcase
            RENDERABLE_IMAGE_EXTENSIONS.include?(ext)
          rescue StandardError
            false
          end

          private

          def normalized_max_image_rows(value)
            rows = value.to_i
            rows.positive? ? rows : nil
          end

          def block_render_metadata(block, block_index)
            {
              cols: @width,
              rows: rows_for(@width),
              placement_id: placement_id_for_block(block, block_index),
            }
          end

          def inline_metadata(inline, cols_available, indent_cols, index)
            src = inline.is_a?(Hash) ? (inline[:src] || inline['src']) : nil
            alt = inline.is_a?(Hash) ? (inline[:alt] || inline['alt']) : nil
            {
              block_type: :image,
              chapter_index: @chapter_index,
              chapter_source_path: @chapter_source_path,
              image: { src: src, alt: alt },
              inline_image: true,
              image_render: {
                cols: cols_available,
                rows: rows_for(cols_available),
                placement_id: placement_id_for_inline(src, index),
                col_offset: indent_cols,
              },
            }
          end

          def image_lines(metadata, rows:)
            Array.new(rows) do |row_index|
              DisplayLine.new(
                text: '',
                segments: [],
                metadata: metadata.merge(
                  image_render_line: row_index.zero?,
                  image_line_index: row_index,
                  image_spacer: !row_index.zero?
                )
              )
            end
          end

          def rows_for(cols)
            estimate = (cols.to_i * 0.5).round
            estimate = estimate.clamp(4, 18)
            estimate = [estimate, @max_image_rows].min if @max_image_rows
            [estimate, 1].max
          rescue StandardError
            8
          end

          def placement_id_for_block(block, block_index)
            image = (block.metadata || {})[:image] || (block.metadata || {})['image'] || {}
            src = image[:src] || image['src'] || ''
            hashed_id("#{chapter_seed}|#{src}|#{block_index}")
          rescue StandardError
            clamp_id(block_index.to_i + 1)
          end

          def placement_id_for_inline(src, index)
            hashed_id("#{chapter_seed}|#{src}|inline|#{index}")
          rescue StandardError
            clamp_id(index.to_i + 1)
          end

          def chapter_seed
            @chapter_source_path.to_s
          end

          def hashed_id(seed)
            raw = Digest::SHA1.digest(seed.to_s)
            int = raw.unpack1('N')
            int.zero? ? 1 : int
          rescue StandardError
            1
          end

          def clamp_id(value)
            int = value.to_i
            int = 1 if int <= 0
            return int if int <= MAX_ID

            reduced = int % MAX_ID
            reduced.zero? ? 1 : reduced
          end
        end
      end
    end
  end
end
