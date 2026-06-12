# frozen_string_literal: true

require_relative '../../../../core/models/content_block'
require_relative '../../../../core/models/block_type'
require_relative '../../../../application/ports/outbound/formatting/display_line'
require_relative '../../terminal/text_metrics'

module Shoko
  module Adapters
    module Output
      module Formatting
        class FormattingService
          # Helper responsible for converting semantic blocks into display-ready
          # lines, preserving inline styles and metadata.
          class LineAssembler
            include Shoko::Core::Models
            include Shoko::Application::Ports::Outbound::Formatting

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

            # Alignment and justification helpers for assembled display lines.
            def align_lines(lines, alignment, block_type: nil)
              align = normalize_alignment(alignment)
              return lines if align.nil? || align == :left
              return align_quote_block(lines, align) if quote_block_alignment?(block_type, align)

              lines.map.with_index do |line, index|
                align_line(line, align, last: index == lines.length - 1)
              end
            end

            def quote_block_alignment?(block_type, align)
              block_type == :quote && %i[center right].include?(align)
            end

            def align_quote_block(lines, align)
              pad = quote_alignment_padding(align, max_quote_visible_length(lines))
              return lines if pad <= 0

              lines.map do |line|
                text = line&.text.to_s
                text.empty? ? line : pad_line_left(line, pad)
              end
            end

            def max_quote_visible_length(lines)
              lines.filter_map do |line|
                text = line&.text.to_s
                next if text.empty?

                visible_text_length(text)
              end.max.to_i
            end

            def quote_alignment_padding(align, max_visible)
              return 0 if max_visible <= 0 || max_visible >= @width

              case align
              when :right
                @width - max_visible
              when :center
                (@width - max_visible) / 2
              else
                0
              end
            end

            def align_line(line, align, last:)
              text = line&.text.to_s
              return line if text.empty?

              visible = visible_text_length(text)
              return line if visible >= @width

              case align
              when :right
                pad_line_left(line, @width - visible)
              when :center
                pad_line_left(line, (@width - visible) / 2)
              when :justify
                last ? line : justify_line(line, @width)
              else
                line
              end
            end

            def pad_line_left(line, padding)
              pad = padding.to_i
              return line if pad <= 0

              prefix = ' ' * pad
              prefix_segment = Shoko::Core::Models::TextSegment.new(text: prefix, styles: {})
              segments = [prefix_segment] + Array(line.segments)
              Shoko::Application::Ports::Outbound::Formatting::DisplayLine.new(
                text: prefix + line.text.to_s,
                segments: segments,
                metadata: line.metadata
              )
            end

            def justify_line(line, width)
              extra = width - visible_text_length(line.text.to_s)
              return line if extra <= 0

              segments = justify_segments(line.segments, extra)
              return line unless segments

              Shoko::Application::Ports::Outbound::Formatting::DisplayLine.new(
                text: segments.map(&:text).join,
                segments: segments,
                metadata: line.metadata
              )
            end

            def justify_segments(segments, extra)
              runs = segment_runs(segments)
              space_indices = distributable_space_indices(runs)
              return nil if space_indices.empty?

              distribute_extra_spaces!(runs, space_indices, extra)
              merged_segments_from_runs(runs)
            end

            def segment_runs(segments)
              Array(segments).each_with_object([]) do |segment, runs|
                seg_text = segment&.text.to_s
                next if seg_text.empty?

                seg_text.scan(/ +|[^ ]+/) do |chunk|
                  runs << { text: chunk, styles: segment.styles || {} }
                end
              end
            end

            def distributable_space_indices(runs)
              indices = runs.each_index.select { |index| runs[index][:text].match?(/\A +\z/) }
              indices.shift if indices.first&.zero?
              indices.pop if indices.last == runs.length - 1
              indices
            end

            def distribute_extra_spaces!(runs, space_indices, extra)
              base = extra / space_indices.length
              remainder = extra % space_indices.length

              space_indices.each_with_index do |index, offset|
                add = base + (offset < remainder ? 1 : 0)
                runs[index][:text] += (' ' * add) if add.positive?
              end
            end

            def merged_segments_from_runs(runs)
              runs.each_with_object([]) do |run, merged|
                next if run[:text].empty?

                if merged.empty? || merged.last.styles != run[:styles]
                  merged << Shoko::Core::Models::TextSegment.new(text: run[:text], styles: run[:styles])
                else
                  previous = merged[-1]
                  merged[-1] = Shoko::Core::Models::TextSegment.new(
                    text: previous.text + run[:text],
                    styles: run[:styles]
                  )
                end
              end
            end

            def normalize_alignment(value)
              return value if value.is_a?(Symbol)

              raw = value.to_s.strip.downcase
              return nil if raw.empty?

              case raw.sub(/;+\z/, '').sub(/\s*!important\z/, '').strip
              when 'left', 'start'
                :left
              when 'right', 'end'
                :right
              when 'center', 'middle'
                :center
              when 'justify'
                :justify
              end
            end

            def visible_text_length(text)
              Shoko::Adapters::Output::Terminal::TextMetrics.visible_length(text)
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
