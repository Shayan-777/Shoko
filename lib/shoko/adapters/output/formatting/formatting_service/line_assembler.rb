# frozen_string_literal: true

require_relative '../../../../core/models/content_block'
require_relative '../../../../core/models/block_type'
require_relative '../../terminal/text_metrics'
require_relative 'line_assembler/alignment_support'

module Shoko
  module Adapters
    module Output
      module Formatting
        class FormattingService
          # Helper responsible for converting semantic blocks into display-ready
          # lines, preserving inline styles and metadata.
          class LineAssembler
            include Shoko::Core::Models
            include AlignmentSupport

            def initialize(width, chapter_index: nil, chapter_source_path: nil, rendering_mode: nil,
                           image_rendering: false, max_image_rows: nil, runtime_config: nil)
              @width = [width.to_i, 10].max
              @chapter_index = chapter_index
              @chapter_source_path = chapter_source_path
              @runtime_config = runtime_config
              @image_rendering = if rendering_mode
                                   rendering_mode == :images
                                 else
                                   image_rendering ? true : false
                                 end
              @image_builder = ImageBuilder.new(
                width: @width,
                chapter_index: chapter_index,
                chapter_source_path: chapter_source_path,
                max_image_rows: max_image_rows
              )
              @text_wrapper = TextWrapper.new(@width, image_builder: @image_builder)
              @table_renderer = TableRenderer.new(@width)
            end

            def build(blocks)
              with_runtime_config do
                blocks.to_a.each_with_index.with_object([]) do |(block, index), lines|
                  lines.concat(lines_for_block(block, index: index))
                  lines << blank_line if blank_line_after?(block, blocks, index)
                end
              end
            end

            private

            def with_runtime_config(&)
              return yield unless @runtime_config

              Shoko::Adapters::Output::Terminal::TextMetrics.with_runtime_config(config: @runtime_config) do
                Tokenizer.with_runtime_config(config: @runtime_config, &)
              end
            end

            def metadata_for(block)
              canonical_type = Shoko::Core::Models::BlockType.canonical(block.type) || block.type
              base = (block.metadata || {}).merge(block_type: canonical_type)
              base[:chapter_index] = @chapter_index if @chapter_index
              base[:chapter_source_path] = @chapter_source_path if @chapter_source_path
              base
            end

            def lines_for_block(block, index:)
              type = block_type(block)
              return table_lines(block) if type == :table
              return preformatted_lines(block) if preformatted?(block)
              return [separator_line] if type == :separator
              return [blank_line] if type == :break
              return image_block_lines(block, index) if type == :image && renderable_image_block?(block)

              wrapped_block_lines(block)
            end

            def preformatted?(block)
              block.type == :code
            end

            def blank_line_after?(block, blocks, index)
              return false if index >= blocks.length - 1
              return true if force_blank_line_after?(block)

              blocks[index + 1]&.type != :list_item
            end

            def force_blank_line_after?(block)
              block.type == :image || block.type == :table || preformatted?(block)
            end

            def renderable_image_block?(block)
              @image_rendering && @image_builder.renderable_block_image?(block)
            end

            def image_block_lines(block, index)
              @image_builder.block_lines(block, block_index: index, base_metadata: metadata_for(block))
            end

            def wrapped_block_lines(block)
              metadata, prefix, continuation_prefix = wrapped_block_options(block)
              type = block_type(block)
              tokens = Tokenizer.tokenize(
                block.segments,
                image_rendering: @image_rendering,
                renderable_image_src: @image_builder.method(:renderable_image_src?)
              )
              lines = @text_wrapper.wrap(tokens,
                                         metadata: metadata,
                                         prefix: prefix,
                                         continuation_prefix: continuation_prefix)
              alignment = metadata[:align]
              align_lines(lines, alignment, block_type: type)
            end

            def wrapped_block_options(block)
              metadata = metadata_for(block)
              type = block_type(block)

              case type
              when :heading
                [metadata, '', '']
              when :list_item
                list_item_options(block, metadata)
              when :quote
                [metadata.merge(block_type: :quote), '│ ', '│ ']
              else
                [metadata, nil, nil]
              end
            end

            def block_type(block)
              Shoko::Core::Models::BlockType.canonical(block.type) || block.type
            end

            def list_item_options(block, metadata)
              indent = '  ' * [block.level.to_i - 1, 0].max
              marker = (block.metadata && block.metadata[:marker]) || '•'
              first_prefix = "#{indent}#{marker} "
              continuation_prefix = indent + (' ' * (marker.to_s.length + 1))
              [metadata.merge(list: true), first_prefix, continuation_prefix]
            end

            def preformatted_lines(block)
              text = block.segments.to_a.map(&:text).join
              style = (block.segments.first&.styles || {}).merge(code: true)

              text.split(/\r?\n/).map do |row|
                plain = row.rstrip
                DisplayLine.new(
                  text: plain,
                  segments: [TextSegment.new(text: plain, styles: style)],
                  metadata: metadata_for(block)
                )
              end
            end

            def separator_line
              bar = '─' * [@width, 40].min
              segment = TextSegment.new(text: bar, styles: { separator: true })
              DisplayLine.new(text: bar, segments: [segment], metadata: { block_type: :separator })
            end

            def blank_line
              DisplayLine.new(text: '', segments: [], metadata: { spacer: true })
            end

            def table_lines(block)
              table_data = block.metadata && block.metadata[:table]
              return preformatted_lines(block) unless table_data

              lines = @table_renderer.render(table_data, base_metadata: metadata_for(block))
              return preformatted_lines(block) if lines.empty?

              lines
            rescue Shoko::Error
              preformatted_lines(block)
            end
          end
        end
      end
    end
  end
end

require_relative 'line_assembler/image_builder'
require_relative 'line_assembler/text_wrapper'
require_relative 'line_assembler/tokenizer'
require_relative 'line_assembler/table_renderer'
