# frozen_string_literal: true

require 'shoko/core/models/content_block'
require 'shoko/core/models/block_type'
require 'shoko/application/ports/outbound/formatting/display_line'
require_relative '../../terminal/text_metrics'

module Shoko
  module Adapters
    module Output
      module Formatting
        class FormattingService
          # Helper responsible for converting semantic blocks into display-ready
          # lines, preserving inline styles and metadata.
          #
          # Typography model: blocks carry optional CSS-derived metadata
          # (spacing_before/after buckets, first_line/hanging indents,
          # indent_left/right margins, alignment, boxed grouping). Between two
          # blocks the larger of the adjacent spacing buckets wins; books
          # without CSS keep the classic one-blank-line separation, headings
          # get room to breathe, and margin-less books render as continuous
          # indented prose the way their designers intended.
          class LineAssembler
            include Shoko::Core::Models
            include Shoko::Application::Ports::Outbound::Formatting

            DEFAULT_BLOCK_SPACING = 1
            HEADING_SPACING_BEFORE = 2
            MAX_BLOCK_SPACING = 2
            BOX_HORIZONTAL_PADDING = 4
            SCENE_BREAK_PATTERN = /\A[*·•⁂❦~✳✻—–\-_=\s]{1,12}\z/

            DEFAULT_TYPOGRAPHY = { paragraph_style: :book, justify: :book }.freeze

            def initialize(width, chapter_index: nil, chapter_source_path: nil, rendering_mode: nil,
                           image_rendering: false, max_image_rows: nil, runtime_config: nil, typography: nil)
              @width = [width.to_i, 10].max
              @chapter_index = chapter_index
              @chapter_source_path = chapter_source_path
              @runtime_config = runtime_config
              @typography = DEFAULT_TYPOGRAPHY.merge(typography || {})
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
              with_runtime_config { assemble(blocks.to_a) }
            end

            private

            def with_runtime_config(&)
              return yield unless @runtime_config

              Shoko::Adapters::Output::Terminal::TextMetrics.with_runtime_config(config: @runtime_config) do
                Tokenizer.with_runtime_config(config: @runtime_config, &)
              end
            end

            def assemble(blocks)
              lines = []
              previous = nil
              previous_boxed = false
              block_units(blocks).each do |unit|
                unit_lines = unit_lines_for(unit)
                next if unit_lines.empty?

                append_gap(lines, unit_gap(previous, previous_boxed, unit))
                lines.concat(unit_lines)
                previous = unit_last(unit)
                previous_boxed = !unit[:box_group].nil?
              end
              lines
            end

            # Framed boxes always get at least one blank line of separation,
            # whatever their inner blocks' margins say.
            def unit_gap(previous, previous_boxed, unit)
              return 0 unless previous

              gap = gap_between(previous, unit_first(unit))
              boxed_adjacent = previous_boxed || !unit[:box_group].nil?
              boxed_adjacent ? [gap, 1].max : gap
            end

            # Groups consecutive blocks that share a boxed group id into one
            # framed unit; every other block is its own unit.
            def block_units(blocks)
              units = []
              blocks.each_with_index do |block, index|
                group = boxable_group_id(block)
                if group && units.last && units.last[:box_group] == group
                  units.last[:blocks] << block
                else
                  units << { blocks: [block], box_group: group, index: index }
                end
              end
              units
            end

            def boxable_group_id(block)
              return nil unless block.metadata

              group = block.metadata[:box_group]
              return nil unless group
              return nil if %i[image table].include?(block_type(block))

              group
            end

            def unit_first(unit)
              unit[:blocks].first
            end

            def unit_last(unit)
              unit[:blocks].last
            end

            def unit_lines_for(unit)
              return boxed_unit_lines(unit[:blocks]) if unit[:box_group]

              lines_for_block(unit[:blocks].first, index: unit[:index])
            end

            def append_gap(lines, gap)
              return if lines.empty?

              gap.times { lines << blank_line }
            end

            def gap_between(previous_block, next_block)
              return 0 if previous_block.type == :break || next_block.type == :break
              return 0 if quiet_list_pair?(previous_block, next_block)

              gap = [spacing_after(previous_block), spacing_before(next_block)].max
              gap.clamp(0, MAX_BLOCK_SPACING)
            end

            # Adjacent list items stay tight unless the book asked for space.
            def quiet_list_pair?(previous_block, next_block)
              previous_block.type == :list_item && next_block.type == :list_item &&
                !explicit_spacing_after?(previous_block) && !explicit_spacing_before?(next_block)
            end

            def spacing_after(block)
              forced = forced_paragraph_spacing(block)
              return forced if forced

              value = block.metadata && block.metadata[:spacing_after]
              return value if value
              return 0 if verse_block?(block)

              DEFAULT_BLOCK_SPACING
            end

            def spacing_before(block)
              return 0 if forced_paragraph_spacing(block)

              value = block.metadata && block.metadata[:spacing_before]
              return value if value
              return 0 if verse_block?(block)
              return HEADING_SPACING_BEFORE if heading_block?(block) && block.heading_level.to_i <= 3

              0
            end

            # The paragraph_style preference overrides the book's own spacing
            # for plain prose paragraphs: :spaced restores the classic blank
            # line, :indent packs paragraphs tight (with a forced first-line
            # indent applied at wrap time).
            def forced_paragraph_spacing(block)
              return nil unless plain_paragraph?(block)

              case @typography[:paragraph_style]
              when :spaced then DEFAULT_BLOCK_SPACING
              when :indent then 0
              end
            end

            def plain_paragraph?(block)
              block_type(block) == :paragraph && block_role(block).nil? && !scene_break?(block)
            end

            def block_role(block)
              block.metadata && block.metadata[:role]
            end

            def verse_block?(block)
              block_role(block) == :verse
            end

            def explicit_spacing_after?(block)
              block.metadata&.key?(:spacing_after)
            end

            def explicit_spacing_before?(block)
              block.metadata&.key?(:spacing_before)
            end

            def heading_block?(block)
              block_type(block) == :heading
            end

            def metadata_for(block)
              canonical_type = Shoko::Core::Models::BlockType.canonical(block.type) || block.type
              base = (block.metadata || {}).merge(block_type: canonical_type)
              base[:chapter_index] = @chapter_index if @chapter_index
              base[:chapter_source_path] = @chapter_source_path if @chapter_source_path
              base
            end

            def lines_for_block(block, index:, max_width: nil)
              type = block_type(block)
              return table_lines(block) if type == :table
              return preformatted_lines(block, max_width: max_width) if preformatted?(block)
              return [separator_line] if type == :separator
              return [blank_line] if type == :break
              return image_block_lines(block, index) if type == :image && renderable_image_block?(block)

              wrapped_block_lines(block, max_width: max_width)
            end

            def preformatted?(block)
              block.type == :code
            end

            def renderable_image_block?(block)
              @image_rendering && @image_builder.renderable_block_image?(block)
            end

            def image_block_lines(block, index)
              @image_builder.block_lines(block, block_index: index, base_metadata: metadata_for(block))
            end

            def wrapped_block_lines(block, max_width: nil)
              effective_width = max_width || @width
              metadata, prefix, continuation_prefix = wrapped_block_options(block)
              minimum_width = [effective_width, 12].min
              wrap_width = [effective_width - metadata[:indent_right].to_i, minimum_width].max
              lines = @text_wrapper.wrap(
                block_tokens(block),
                metadata: metadata, prefix: prefix, continuation_prefix: continuation_prefix,
                max_width: wrap_width
              )
              lines = dim_lines(lines) if dimmed_block?(block)
              align_lines(lines, alignment_for_block(block, metadata), block_type: block_type(block),
                                                                       width: wrap_width)
            end

            def dimmed_block?(block)
              scene_break?(block) || %i[subtitle caption].include?(block_role(block))
            end

            def block_tokens(block)
              Tokenizer.tokenize(
                block.segments,
                image_rendering: @image_rendering,
                renderable_image_src: @image_builder.method(:renderable_image_src?)
              )
            end

            def alignment_for_block(block, metadata)
              align = metadata[:align] || default_alignment(block)
              apply_justify_preference(align, block)
            end

            def apply_justify_preference(align, block)
              case @typography[:justify]
              when :on
                return :justify if plain_paragraph?(block) && (align.nil? || align == :left)
              when :off
                return nil if align == :justify
              end
              align
            end

            # Untyped defaults: chapter-level headings and image placeholders
            # center; scene breaks center. Books that specified an alignment
            # (including :left) always win.
            def default_alignment(block)
              type = block_type(block)
              return :center if type == :heading && block.heading_level.to_i <= 2
              return :center if type == :image
              return :center if %i[subtitle caption].include?(block_role(block))
              return :center if scene_break?(block)

              nil
            end

            def scene_break?(block)
              return false unless block_type(block) == :paragraph

              text = block.text
              !text.strip.empty? && SCENE_BREAK_PATTERN.match?(text)
            end

            def dim_lines(lines)
              lines.map do |line|
                segments = line.segments.map do |segment|
                  TextSegment.new(text: segment.text, styles: (segment.styles || {}).merge(dim: true))
                end
                DisplayLine.new(text: line.text, segments: segments, metadata: line.metadata)
              end
            end

            def wrapped_block_options(block)
              metadata, first, continuation = base_block_options(block)
              indent_first, indent_continuation = indent_prefixes(metadata, block)
              [metadata, "#{first}#{indent_first}", "#{continuation}#{indent_continuation}"]
            end

            def base_block_options(block)
              metadata = metadata_for(block)
              case block_type(block)
              when :list_item
                list_item_options(block, metadata)
              when :quote
                quote_options(block, metadata)
              else
                [metadata, '', '']
              end
            end

            # Epigraphs are set as plain italic text in books — the gutter bar
            # is the terminal idiom for quoted prose, not for chapter mottos.
            def quote_options(block, metadata)
              return [metadata.merge(block_type: :quote), '', ''] if block_role(block) == :epigraph

              [metadata.merge(block_type: :quote), '│ ', '│ ']
            end

            def indent_prefixes(metadata, block)
              left = ' ' * metadata[:indent_left].to_i
              first_line = ' ' * first_line_indent_cols(metadata, block)
              hanging_cols = metadata[:hanging_indent].to_i
              hanging_cols = 2 if hanging_cols.zero? && verse_block?(block)
              ["#{left}#{first_line}", "#{left}#{' ' * hanging_cols}"]
            end

            def first_line_indent_cols(metadata, block)
              if plain_paragraph?(block)
                case @typography[:paragraph_style]
                when :spaced then return 0
                when :indent then return [metadata[:first_line_indent].to_i, 2].max
                end
              end
              metadata[:first_line_indent].to_i
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

            # Wraps a run of boxed blocks at a narrower width and frames the
            # result with light box-drawing borders.
            def boxed_unit_lines(blocks)
              inner_width = [@width - BOX_HORIZONTAL_PADDING, 10].max
              inner = boxed_inner_lines(blocks, inner_width)
              return [] if inner.empty?

              frame_lines(inner, inner_width)
            end

            def boxed_inner_lines(blocks, inner_width)
              inner = []
              previous = nil
              blocks.each do |block|
                block_lines = lines_for_block(block, index: nil, max_width: inner_width)
                next if block_lines.empty?

                append_gap(inner, previous ? gap_between(previous, block) : 0)
                inner.concat(block_lines)
                previous = block
              end
              inner
            end

            def frame_lines(inner, inner_width)
              metadata = (inner.first&.metadata || {}).merge(boxed: true)
              horizontal = '─' * (inner_width + 2)
              [boxed_border_line("┌#{horizontal}┐", metadata)] +
                inner.map { |line| boxed_content_line(line, inner_width) } +
                [boxed_border_line("└#{horizontal}┘", metadata)]
            end

            def boxed_border_line(text, metadata)
              segment = TextSegment.new(text: text, styles: { dim: true })
              DisplayLine.new(text: text, segments: [segment], metadata: metadata)
            end

            def boxed_content_line(line, inner_width)
              pad = [inner_width - visible_text_length(line.text.to_s), 0].max
              border = { dim: true }
              segments = [TextSegment.new(text: '│ ', styles: border)] +
                         Array(line.segments) +
                         [TextSegment.new(text: "#{' ' * pad} │", styles: border)]
              DisplayLine.new(
                text: "│ #{line.text}#{' ' * pad} │",
                segments: segments,
                metadata: (line.metadata || {}).merge(boxed: true)
              )
            end

            def preformatted_lines(block, max_width: nil)
              metadata = metadata_for(block)
              preformatted_rows(block.segments).map do |row_segments|
                trimmed = trim_row_end(row_segments)
                trimmed = clip_row(trimmed, max_width) if max_width
                DisplayLine.new(
                  text: trimmed.map(&:text).join,
                  segments: trimmed,
                  metadata: metadata
                )
              end
            end

            # Splits styled code segments into per-line segment rows, keeping each
            # run's own inline styles instead of flattening to the first segment's.
            def preformatted_rows(segments)
              rows = [[]]
              segments.to_a.each do |segment|
                styles = (segment.styles || {}).merge(code: true)
                segment.text.to_s.delete("\r").split("\n", -1).each_with_index do |part, index|
                  rows << [] if index.positive?
                  rows.last << TextSegment.new(text: part, styles: styles) unless part.empty?
                end
              end
              rows
            end

            def trim_row_end(row_segments)
              trimmed = row_segments.dup
              while (last = trimmed.last)
                text = last.text.to_s.sub(/\s+\z/, '')
                break trimmed[-1] = TextSegment.new(text: text, styles: last.styles) unless text.empty?

                trimmed.pop
              end
              trimmed
            end

            def clip_row(row_segments, max_width)
              remaining = max_width
              row_segments.each_with_object([]) do |segment, clipped|
                break clipped if remaining <= 0

                text = Shoko::Adapters::Output::Terminal::TextMetrics.truncate_to(segment.text.to_s, remaining)
                next if text.empty?

                clipped << TextSegment.new(text: text, styles: segment.styles)
                remaining -= visible_text_length(text)
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
            def align_lines(lines, alignment, block_type: nil, width: nil)
              align = normalize_alignment(alignment)
              return lines if align.nil? || align == :left

              target_width = width || @width
              return align_quote_block(lines, align, target_width) if quote_block_alignment?(block_type, align)

              lines.map.with_index do |line, index|
                align_line(line, align, target_width, last: index == lines.length - 1)
              end
            end

            def quote_block_alignment?(block_type, align)
              block_type == :quote && %i[center right].include?(align)
            end

            def align_quote_block(lines, align, width)
              pad = quote_alignment_padding(align, max_quote_visible_length(lines), width)
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

            def quote_alignment_padding(align, max_visible, width)
              return 0 if max_visible <= 0 || max_visible >= width

              case align
              when :right
                width - max_visible
              when :center
                (width - max_visible) / 2
              else
                0
              end
            end

            def align_line(line, align, width, last:)
              text = line&.text.to_s
              return line if text.empty?

              visible = visible_text_length(text)
              return line if visible >= width

              case align
              when :right
                pad_line_left(line, width - visible)
              when :center
                pad_line_left(line, (width - visible) / 2)
              when :justify
                last ? line : justify_line(line, width)
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
              runs.pop while runs.last && runs.last[:text].match?(/\A +\z/)
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
