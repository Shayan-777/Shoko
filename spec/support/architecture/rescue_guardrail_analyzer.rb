# frozen_string_literal: true

module SpecSupport
  module Architecture
    # Shared analyzer used by architecture guardrails for rescue/fallback cleanup.
    module RescueGuardrailAnalyzer
      module_function

      LITERAL_DEFAULT_PATTERNS = [
        /^return\s+nil\b|^nil\b/,
        /^return\s+false\b|^false\b/,
        /^return\s+\[\]\b|^\[\]\b/,
        /^return\s+\{\}\b|^\{\}\b/,
        /^return\s+''\b|^''\b|^return\s+""\b|^""\b/,
        /^return\s+:[A-Za-z_][A-Za-z0-9_]*\b|^:[A-Za-z_][A-Za-z0-9_]*\b/
      ].freeze

      def fallback_literal_rescue_offenders(lib_root:)
        files = Dir[File.join(lib_root, '**', '*.rb')]
        offenders = []

        files.each do |path|
          lines = File.readlines(path)
          lines.each_with_index do |line, index|
            next unless line.match?(/^\s*rescue\b/)

            next_line = next_significant_line(lines, index + 1)
            next unless next_line
            next unless literal_default_line?(next_line[:content])

            offenders << "#{relative(path, lib_root)}:#{index + 1} -> #{next_line[:content].strip}"
          end
        end

        offenders
      end

      def overlapping_rescue_chain_offenders(lib_root:)
        files = Dir[File.join(lib_root, '**', '*.rb')]
        offenders = []

        files.each do |path|
          lines = File.readlines(path)
          lines.each_index do |index|
            current = parse_rescue_header(lines[index])
            next unless current

            current_indent = current[:indent]
            current_classes = current[:classes]
            neighbor_index = find_next_same_indent_rescue(lines, index, current_indent)
            next unless neighbor_index

            neighbor = parse_rescue_header(lines[neighbor_index])
            next unless neighbor

            overlap = current_classes & neighbor[:classes]
            next if overlap.empty?

            body_lines = lines[(index + 1)...neighbor_index]
            next unless body_lines.any? { |line| line.strip.start_with?('raise') }

            offenders << "#{relative(path, lib_root)}:#{index + 1} overlaps #{neighbor_index + 1} on #{overlap.join(', ')}"
          end
        end

        offenders
      end

      def stale_optional_resolution_offenders(lib_root:)
        files = Dir[File.join(lib_root, '**', '*.rb')]
        pattern = /\boptional\s*\?\s*container\.resolve\(key\)\s*:\s*container\.resolve\(key\)/

        files.filter_map do |path|
          rel = relative(path, lib_root)
          next unless File.readlines(path).any? { |line| line.match?(pattern) }

          rel
        end
      end

      def standard_error_rescue_offenders(lib_root:)
        files = Dir[File.join(lib_root, '**', '*.rb')]
        files.filter_map do |path|
          rel = relative(path, lib_root)
          next unless File.readlines(path).any? { |line| line.match?(/\brescue\s+StandardError\b/) }

          rel
        end
      end

      def fallback_literal_count(lib_root:)
        fallback_literal_rescue_offenders(lib_root:).length
      end

      def relative(path, lib_root)
        path.delete_prefix("#{lib_root}/")
      end

      def literal_default_line?(content)
        stripped = content.strip
        LITERAL_DEFAULT_PATTERNS.any? { |pattern| stripped.match?(pattern) }
      end

      def next_significant_line(lines, start_index)
        index = start_index
        while index < lines.length
          stripped = lines[index].strip
          unless stripped.empty? || stripped.start_with?('#')
            return { line: index + 1, content: lines[index] }
          end
          index += 1
        end
        nil
      end

      def parse_rescue_header(line)
        match = line.match(/^(\s*)rescue\s+(.+?)\s*(?:=>\s*\w+)?\s*$/)
        return nil unless match

        {
          indent: match[1].size,
          classes: match[2].split(',').map(&:strip)
        }
      end

      def find_next_same_indent_rescue(lines, from_index, indent)
        index = from_index + 1
        while index < lines.length
          line = lines[index]
          end_match = line.match(/^(\s*)end\b/)
          break if end_match && end_match[1].size <= indent

          rescue_match = line.match(/^(\s*)rescue\b/)
          return index if rescue_match && rescue_match[1].size == indent

          index += 1
        end
        nil
      end

      module_function :relative,
                      :literal_default_line?,
                      :next_significant_line,
                      :parse_rescue_header,
                      :find_next_same_indent_rescue
    end
  end
end
