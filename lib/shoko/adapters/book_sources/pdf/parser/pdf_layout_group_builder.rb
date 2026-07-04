# frozen_string_literal: true

module Shoko
  module Adapters
    module BookSources
      module Pdf
        # Builds semantic layout groups from normalized lines.
        class PdfLayoutGroupBuilder
          # Average glyph advance per character class, in em. Only relative
          # consistency matters: the same estimator produces both the column
          # right edge and a candidate line's right edge, so its systematic
          # bias cancels out of the comparison.
          CHAR_WIDTH_EMS = { space: 0.26, narrow: 0.32, wide: 0.66, extra_wide: 0.92, default: 0.5 }.freeze
          NARROW_CHAR = /[.,;:!'’‘`|()\[\]{}ijltfr-]/
          EXTRA_WIDE_CHAR = /[mwMW—]/
          WIDE_CHAR = /[A-Z0-9]/

          def line_metrics(lines)
            x_values = content_x_values(lines)
            baseline_x = baseline_x_for(x_values)
            metrics = geometry_metrics(x_values, baseline_x).merge(text_metrics(lines))
            metrics.merge(edge_metrics(lines, metrics))
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

          # Estimated column right edge and the book's paragraph indent stop
          # (both nil when the layout data cannot support them).
          def edge_metrics(lines, metrics)
            content = lines.reject { |line| line[:break] }
            {
              column_right_x: column_right_estimate(content, metrics),
              indent_x: indent_stop_estimate(content, metrics),
            }
          end

          # Median estimated right edge over long baseline-anchored body lines.
          # Justified prose fills those lines to the true margin, so the median
          # is robust even though individual estimates wobble.
          def column_right_estimate(content, metrics)
            baseline_x = metrics[:baseline_x].to_f
            edges = content.filter_map do |line|
              next unless body_edge_sample?(line, baseline_x)

              line[:x] + estimate_text_width(line[:text], line[:font_size])
            end
            return nil if edges.length < 5

            median(edges)
          end

          def body_edge_sample?(line, baseline_x)
            x = line[:x]
            return false unless x && line[:font_size].to_f.positive?
            return false if line[:bold]
            return false unless (x - baseline_x).abs <= 8.0

            line[:text].to_s.strip.length >= 30
          end

          # The x position paragraphs indent their first line to, when the book
          # uses indent-style paragraphs: a consistent cluster of line starts
          # roughly one em right of the baseline.
          def indent_stop_estimate(content, metrics)
            body_font = metrics[:body_font_size].to_f
            return nil unless body_font.positive?

            baseline_x = metrics[:baseline_x].to_f
            deltas = indent_candidate_deltas(content, baseline_x, body_font)
            return nil if deltas.length < 4 || deltas.length < content.length * 0.04

            candidate = median(deltas)
            consistent_indent_cluster?(deltas, candidate, body_font) ? baseline_x + candidate : nil
          end

          def consistent_indent_cluster?(deltas, candidate, body_font)
            near = deltas.count { |delta| (delta - candidate).abs <= body_font * 0.25 }
            near >= deltas.length * 0.8
          end

          def indent_candidate_deltas(content, baseline_x, body_font)
            content.filter_map do |line|
              x = line[:x]
              next unless x

              delta = x - baseline_x
              delta if delta > body_font * 0.4 && delta <= body_font * 2.4
            end
          end

          def estimate_text_width(text, font_size)
            ems = text.to_s.each_char.sum { |char| char_width_em(char) }
            ems * font_size.to_f
          end

          def char_width_em(char)
            return CHAR_WIDTH_EMS[:space] if char == ' '
            return CHAR_WIDTH_EMS[:extra_wide] if EXTRA_WIDE_CHAR.match?(char)
            return CHAR_WIDTH_EMS[:wide] if WIDE_CHAR.match?(char)
            return CHAR_WIDTH_EMS[:narrow] if NARROW_CHAR.match?(char)

            CHAR_WIDTH_EMS[:default]
          end

          def median(values)
            sorted = values.sort
            sorted[sorted.length / 2]
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
              state: { content_index: -1, preamble_open: true, in_references: false,
                       page_continuation: false, section_gap: false },
            }
          end

          def step_traversal(traversal, line, idx)
            return handle_break_line(traversal, line, idx) if line[:break]

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

          # A page boundary mid-sentence is not a paragraph boundary: keep the
          # open paragraph and let the next page's first line continue it. A
          # whitespace spacer line, by contrast, is a deliberate section gap.
          def handle_break_line(traversal, line, idx)
            if line[:page] && page_continuation?(traversal, idx)
              traversal[:state][:page_continuation] = true
              return
            end

            traversal[:current] = flush_group(traversal[:current], traversal[:groups])
            traversal[:state][:section_gap] = true unless line[:page]
          end

          def page_continuation?(traversal, idx)
            current = traversal[:current]
            return false unless current && current[:kind] == :paragraph
            return false unless full_measure_line?(current[:lines].last, traversal[:metrics])
            return false if sentence_terminal?(current[:lines].last[:text])

            next_line = next_content_line(traversal[:lines], idx)
            return false unless next_line

            !indent_stop_line?(next_line, traversal[:metrics])
          end

          # A paragraph interrupted by a page boundary was cut mid-flow, so its
          # last line ran (close to) the full measure. Short fragments before a
          # page break are labels or genuinely-ending paragraphs — never merge.
          def full_measure_line?(line, metrics)
            body_length = metrics[:body_line_length].to_f
            return false unless body_length.positive?

            line[:text].to_s.strip.length >= body_length * 0.6
          end

          def sentence_terminal?(text)
            compact = text.to_s.strip
            compact.empty? || compact.match?(/[.!?:;…]["')\]”’]?\z/)
          end

          def indent_stop_line?(line, metrics)
            indent_x = metrics[:indent_x]
            return false unless indent_x && line[:x]

            (line[:x] - indent_x).abs <= indent_stop_tolerance(metrics)
          end

          def indent_stop_tolerance(metrics)
            [metrics[:body_font_size].to_f * 0.25, 3.0].max
          end

          def consume_content_line(lines:, idx:, line:, metrics:, heuristics:, current:, groups:, state:)
            previous_kind = current ? current[:kind] : groups.last&.[](:kind)
            context = line_context(lines, idx, metrics, previous_kind)
            carried = { page_continuation: state[:page_continuation], section_gap: state[:section_gap] }
            state = advance_state(state, line, context, heuristics)
            signature = group_signature(line, context, state, heuristics)
            merge = { signature: signature, line: line, metrics: metrics, carried: carried }
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
            { content_index: content_index, preamble_open: preamble_open, in_references: in_references,
              page_continuation: false, section_gap: false }
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
            new_group(signature, merge)
          end

          def new_group(signature, merge)
            group = { kind: signature[:kind], align: signature[:align], lines: [merge[:line]] }
            group[:level] = signature[:level] if signature[:level]
            group[:marker] = signature[:marker] if signature[:marker]
            group[:font_size] = signature[:font_size] if signature[:font_size]
            group[:section_start] = true if merge.dig(:carried, :section_gap)
            group[:indent_start] = true if indent_stop_line?(merge[:line], merge[:metrics])
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
            # First line after a suppressed page-boundary flush: the paragraph
            # was cut mid-sentence, so it continues regardless of break rules
            # (the y-gap across pages would otherwise read as a spike).
            return true if merge.dig(:carried, :page_continuation) && signature[:kind] == :paragraph
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
            # In an indent-style book a line at the indent stop is a paragraph
            # opener even when the previous line ran the full measure.
            return true if indent_stop_line?(line, metrics)
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

          # Alignment classification. When the column's right edge can be
          # estimated, a line is centered when its left and right gaps balance
          # and right-aligned when its right edge reaches the margin —
          # regardless of where it starts. The start-position cutoffs remain
          # as the fallback for payloads without font sizes.
          def alignment_for(line, metrics)
            x = line[:x]
            return :left unless x

            delta = x - metrics[:baseline_x].to_f
            return :left if delta <= left_tolerance(metrics)
            # A line at the book's paragraph indent stop is an indent, never
            # an alignment.
            return :left if indent_stop_line?(line, metrics)

            edge_alignment_for(line, delta, metrics) || legacy_alignment_for(delta, metrics)
          end

          def edge_alignment_for(line, delta, metrics)
            column_right = metrics[:column_right_x]
            font_size = line[:font_size].to_f
            return nil unless column_right && font_size.positive?

            right_gap = column_right - (line[:x] + estimate_text_width(line[:text], font_size))
            usable = [column_right - metrics[:baseline_x].to_f, 1.0].max
            gap_alignment(delta, right_gap, usable, font_size)
          end

          # Centered lines balance a *substantial* gap on each side; a line
          # whose estimated width nearly fills the measure is body text no
          # matter how the estimate wobbles. Right alignment needs the right
          # edge at the margin and a large left offset.
          def gap_alignment(delta, right_gap, usable, font_size)
            min_gap = [usable * 0.06, font_size * 1.2].max
            balanced = (delta - right_gap).abs <= [usable * 0.12, font_size * 2.5].max
            return :center if right_gap >= min_gap && balanced
            return :right if right_gap <= min_gap && delta >= usable * 0.18

            :left
          end

          def legacy_alignment_for(delta, metrics)
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
