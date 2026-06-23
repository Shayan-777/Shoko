# frozen_string_literal: true

module Shoko
  module Adapters
    module BookSources
      module Pdf
        # Builds semantic layout groups from normalized lines.
        class PdfLayoutGroupBuilder
          def line_metrics(lines)
            x_values = content_x_values(lines)
            baseline_x = baseline_x_for(x_values)
            geometry_metrics(x_values, baseline_x).merge(text_metrics(lines))
          end

          def build_groups(lines, metrics:, heuristics:)
            groups, current = traverse_lines(lines, metrics: metrics, heuristics: heuristics)
            flush_group(current, groups)
            groups
          end

          private

          def geometry_metrics(x_values, baseline_x)
            max_ref_x = max_ref_x_for(x_values, baseline_x)
            min_x = x_values.min || 0.0
            max_x = x_values.max || baseline_x
            {
              min_x: min_x,
              max_x: max_x,
              baseline_x: baseline_x,
              max_ref_x: max_ref_x,
              span: [max_x - min_x, 1.0].max,
              ref_span: [max_ref_x - baseline_x, 1.0].max,
            }
          end

          def text_metrics(lines)
            body_font_size = body_font_size_for(lines)
            {
              body_font_size: body_font_size,
              heading_levels: heading_levels_for(lines, body_font_size),
              body_line_length: body_line_length_for(lines),
            }
          end

          def traverse_lines(lines, metrics:, heuristics:)
            traversal = build_traversal_state(lines, metrics, heuristics)
            lines.each_with_index { |line, idx| step_traversal(traversal, line, idx) }
            [traversal[:groups], traversal[:current]]
          end

          def build_traversal_state(lines, metrics, heuristics)
            {
              lines: lines,
              metrics: metrics,
              heuristics: heuristics,
              groups: [],
              current: nil,
              state: { content_index: -1, preamble_open: true, in_references: false },
            }
          end

          def step_traversal(traversal, line, idx)
            if line[:break]
              traversal[:current] = flush_group(traversal[:current], traversal[:groups])
              return
            end

            traversal[:current], traversal[:state] = consume_content_line(
              lines: traversal[:lines],
              idx: idx,
              line: line,
              metrics: traversal[:metrics],
              heuristics: traversal[:heuristics],
              current: traversal[:current],
              groups: traversal[:groups],
              state: traversal[:state]
            )
          end

          def consume_content_line(lines:, idx:, line:, metrics:, heuristics:, current:, groups:, state:)
            previous_kind = current ? current[:kind] : groups.last&.[](:kind)
            context = line_context(lines, idx, metrics, previous_kind)
            state = advance_state(state, line, context, heuristics)
            signature = group_signature(line, context, state, heuristics)
            merge = { signature: signature, line: line, metrics: metrics }
            [merge_or_start_group(current, groups, merge), state]
          end

          def flush_group(current, groups)
            groups << current if current
            nil
          end

          def content_x_values(lines)
            lines.each_with_object([]) do |line, x_values|
              next if line[:break]

              x = line[:x]
              x_values << x if x
            end
          end

          # Body size = the most common font size among non-bold content lines
          # (the running prose); headings/titles are the larger or bold outliers.
          def body_font_size_for(lines)
            content = lines.reject { |line| line[:break] }
            prose = content.reject { |line| line[:bold] }
            sizes = font_sizes(prose.empty? ? content : prose)
            return nil if sizes.empty?

            sizes.tally.max_by { |_size, count| count }&.first
          end

          def font_sizes(lines)
            lines.filter_map { |line| line[:font_size] }
          end

          # Distinct sizes strictly larger than body, ranked: the largest is
          # heading level 1, the next level 2, and so on.
          def heading_levels_for(lines, body_font_size)
            return {} unless body_font_size

            larger = lines.reject { |line| line[:break] }
                          .filter_map { |line| line[:font_size] }
                          .select { |size| size > body_font_size * 1.05 }
                          .uniq.sort.reverse
            larger.each_with_index.to_h { |size, idx| [size, idx + 1] }
          end

          # Median character length of body lines. A paragraph's last line is
          # noticeably shorter than this (justified text fills every other line to
          # the margin), which is the most reliable break signal when PDF y-coords
          # are unreliable.
          def body_line_length_for(lines)
            lengths = lines.reject { |line| line[:break] || line[:bold] }
                           .map { |line| line[:text].to_s.strip.length }
                           .reject(&:zero?)
            return nil if lengths.empty?

            sorted = lengths.sort
            sorted[sorted.length / 2]
          end

          def baseline_x_for(x_values)
            percentile_x(x_values, 0.15) || (x_values.min || 0.0)
          end

          def max_ref_x_for(x_values, baseline_x)
            percentile_x(x_values, 0.995) || (x_values.max || baseline_x)
          end

          def line_context(lines, idx, metrics, previous_kind)
            line = lines[idx]
            {
              align: alignment_for(line, metrics),
              previous_kind: previous_kind,
              next_line: next_content_line(lines, idx),
              prev_line: previous_content_line(lines, idx),
              prev_break: previous_is_break?(lines, idx),
              next_break: next_is_break?(lines, idx),
              font_size: line[:font_size],
              bold: line[:bold],
              body_font_size: metrics[:body_font_size],
              heading_levels: metrics[:heading_levels] || {},
            }
          end

          def advance_state(state, line, context, heuristics)
            content_index = state[:content_index] + 1
            preamble_open = state[:preamble_open]
            if preamble_open && heuristics.body_line_candidate?(
              line,
              context[:align],
              content_index,
              previous_kind: context[:previous_kind],
              next_line: context[:next_line]
            )
              preamble_open = false
            end
            in_references = state[:in_references] || references_section_start?(line, context, heuristics)
            { content_index: content_index, preamble_open: preamble_open, in_references: in_references }
          end

          # The references/bibliography heading flips the rest of the chapter into
          # reference mode, where each entry becomes its own block.
          def references_section_start?(line, context, heuristics)
            heuristics.reference_heading?(line[:text]) &&
              heuristics.heading_line?(line[:text], context[:align], context)
          end

          def group_signature(line, context, state, heuristics)
            kind = group_kind(line, context, state, heuristics)
            align = normalize_group_alignment(kind, context[:align], preamble_open: state[:preamble_open])
            signature = { kind: kind, align: align }
            if kind == :heading
              signature[:level] = heuristics.heading_level(context)
              signature[:font_size] = context[:font_size]
            end
            signature[:marker] = heuristics.list_marker(line[:text]) if kind == :list_item
            signature[:reference_start] = heuristics.reference_entry_start?(line[:text]) if kind == :reference
            signature
          end

          def group_kind(line, context, state, heuristics)
            return :list_item if !state[:in_references] && heuristics.list_item?(line[:text], context)
            return :heading if heuristics.heading_line?(line[:text], context[:align], context)
            return :reference if state[:in_references]
            return :epigraph if heuristics.epigraph_line?(
              line,
              context[:align],
              state[:content_index],
              previous_kind: context[:previous_kind],
              next_line: context[:next_line],
              preamble_open: state[:preamble_open]
            )

            :paragraph
          end

          def merge_or_start_group(current, groups, merge)
            signature = merge[:signature]
            return append_to_group(current, signature, merge[:line]) if mergeable_group?(current, merge)

            groups << current if current
            new_group(signature, merge[:line])
          end

          def new_group(signature, line)
            group = { kind: signature[:kind], align: signature[:align], lines: [line] }
            group[:level] = signature[:level] if signature[:level]
            group[:marker] = signature[:marker] if signature[:marker]
            group[:font_size] = signature[:font_size] if signature[:font_size]
            group
          end

          def append_to_group(current, signature, line)
            if signature[:kind] == :epigraph && (current[:align] == :right || signature[:align] == :right)
              current[:align] = :right
            elsif current[:kind] == :heading && centered_alignment?(signature[:align])
              # A wrapped title's full-width first line starts at the left margin and
              # reads as left-aligned; a later short line reveals the block is
              # centered. One centered line centers the whole heading.
              current[:align] = :center
            end
            current[:lines] << line
            current
          end

          def centered_alignment?(align)
            %i[center right].include?(align)
          end

          def mergeable_group?(current, merge)
            return false unless current

            signature = merge[:signature]
            # Consecutive heading lines of the same size are one wrapped heading
            # (e.g. a two-line title); everything else keeps headings separate.
            return heading_continuation?(current, signature) if signature[:kind] == :heading
            return false if signature[:kind] == :list_item
            # A marker-less line right after a list item is its wrapped continuation.
            return true if list_continuation?(current, signature)
            return false unless current[:kind] == signature[:kind]

            same_kind_continuation?(current, merge)
          end

          def same_kind_continuation?(current, merge)
            signature = merge[:signature]
            # In the references section a new author/numbered signature starts a new
            # entry; every other line is a wrapped continuation of the entry above.
            return !signature[:reference_start] if current[:kind] == :reference
            return false if paragraph_break?(current, merge[:line], signature, merge[:metrics])

            signature[:kind] == :epigraph || current[:align] == signature[:align]
          end

          def list_continuation?(current, signature)
            current[:kind] == :list_item && signature[:kind] == :paragraph
          end

          # Same-size adjacent heading lines belong to one heading. Distinct
          # section headings are separated by body text, so they never collide
          # here; differing sizes (title vs. section) keep them apart.
          def heading_continuation?(current, signature)
            current[:kind] == :heading && same_font_size?(current[:font_size], signature[:font_size])
          end

          def same_font_size?(first, second)
            return false unless first && second

            (first - second).abs < 0.5
          end

          # A new body paragraph starts after the previous paragraph's short last
          # line, or on a local vertical-gap spike (for PDFs whose y-coords are
          # reliable and that space paragraphs out). The spike compares against the
          # immediately preceding gap, so it is immune to the slow coordinate drift
          # some PDFs exhibit.
          def paragraph_break?(current, line, signature, metrics)
            return false unless signature[:kind] == :paragraph
            return true if short_line_paragraph_end?(current[:lines].last, metrics)

            gap_spike?(current[:lines], line)
          end

          def short_line_paragraph_end?(previous, metrics)
            text = previous[:text].to_s.strip
            return false unless text.match?(/[.!?]["')\]”’]?\z/)

            body_length = metrics[:body_line_length].to_f
            return false unless body_length.positive?

            text.length < body_length * 0.72
          end

          def gap_spike?(prev_lines, line)
            return false if prev_lines.length < 2

            recent_gap = vertical_gap(prev_lines[-2], prev_lines[-1])
            new_gap = vertical_gap(prev_lines[-1], line)
            return false unless recent_gap&.positive? && new_gap

            new_gap > recent_gap * 1.5 && (new_gap - recent_gap) > 3.0
          end

          def vertical_gap(previous, line)
            return nil unless previous && line && previous[:y] && line[:y]

            (previous[:y] - line[:y]).abs
          end

          def normalize_group_alignment(kind, align, preamble_open:)
            return align unless kind == :paragraph
            return align if preamble_open

            :left
          end

          def alignment_for(line, metrics)
            x = line[:x]
            return :left unless x

            delta = x - metrics[:baseline_x].to_f
            return :left if delta <= left_tolerance(metrics)
            return :right if delta >= right_cutoff(metrics)
            return :center if delta >= center_cutoff(metrics)

            :left
          end

          def next_content_line(lines, start_idx)
            idx = start_idx.to_i + 1
            while idx < lines.length
              line = lines[idx]
              return line unless line[:break]

              idx += 1
            end
            nil
          end

          def previous_content_line(lines, start_idx)
            idx = start_idx.to_i - 1
            while idx >= 0
              line = lines[idx]
              return line unless line[:break]

              idx -= 1
            end
            nil
          end

          def previous_is_break?(lines, idx)
            pos = idx.to_i - 1
            return true if pos.negative?

            lines[pos][:break] == true
          end

          def next_is_break?(lines, idx)
            pos = idx.to_i + 1
            return true if pos >= lines.length

            lines[pos][:break] == true
          end

          def left_tolerance(metrics)
            (metrics[:ref_span].to_f * 0.10).clamp(8.0, 22.0)
          end

          def center_cutoff(metrics)
            (metrics[:ref_span].to_f * 0.22).clamp(38.0, 180.0)
          end

          def right_cutoff(metrics)
            cutoff = (metrics[:ref_span].to_f * 0.70).clamp(64.0, 360.0)
            [cutoff, center_cutoff(metrics) + 18.0].max
          end

          def percentile_x(values, percentile)
            sorted = Array(values).map(&:to_f).sort
            return nil if sorted.empty?

            position = percentile.to_f.clamp(0.0, 1.0)
            index = ((sorted.length - 1) * position).floor
            sorted[index]
          end
        end
      end
    end
  end
end
