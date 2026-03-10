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

          def build_groups(lines, metrics:, heuristics:)
            groups, current = traverse_lines(lines, metrics: metrics, heuristics: heuristics)
            flush_group(current, groups)
            groups
          end

          private

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
              state: { content_index: -1, preamble_open: true },
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
            [merge_or_start_group(current, groups, signature, line), state]
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

          def baseline_x_for(x_values)
            percentile_x(x_values, 0.15) || (x_values.min || 0.0)
          end

          def max_ref_x_for(x_values, baseline_x)
            percentile_x(x_values, 0.995) || (x_values.max || baseline_x)
          end

          def line_context(lines, idx, metrics, previous_kind)
            {
              align: alignment_for(lines[idx], metrics),
              previous_kind: previous_kind,
              next_line: next_content_line(lines, idx),
              prev_line: previous_content_line(lines, idx),
              prev_break: previous_is_break?(lines, idx),
              next_break: next_is_break?(lines, idx),
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
            { content_index: content_index, preamble_open: preamble_open }
          end

          def group_signature(line, context, state, heuristics)
            kind = group_kind(line, context, state, heuristics)
            align = normalize_group_alignment(kind, context[:align], preamble_open: state[:preamble_open])
            { kind: kind, align: align }
          end

          def group_kind(line, context, state, heuristics)
            return :heading if heuristics.heading_line?(line[:text], context[:align], context)
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

          def merge_or_start_group(current, groups, signature, line)
            return append_to_group(current, signature, line) if mergeable_group?(current, signature)

            groups << current if current
            { kind: signature[:kind], align: signature[:align], lines: [line] }
          end

          def append_to_group(current, signature, line)
            if signature[:kind] == :epigraph && (current[:align] == :right || signature[:align] == :right)
              current[:align] = :right
            end
            current[:lines] << line
            current
          end

          def mergeable_group?(current, signature)
            return false unless current
            return false if signature[:kind] == :heading
            return false unless current[:kind] == signature[:kind]

            signature[:kind] == :epigraph || current[:align] == signature[:align]
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
