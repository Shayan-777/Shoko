# frozen_string_literal: true

module Shoko
  module Adapters
    module Output
      module Formatting
        class FormattingService
          class LineAssembler
            # Alignment and justification helpers for assembled display lines.
            module AlignmentSupport
              private

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
                Shoko::Core::Models::DisplayLine.new(
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

                Shoko::Core::Models::DisplayLine.new(
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
end
