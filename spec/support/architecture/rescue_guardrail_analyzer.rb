# frozen_string_literal: true

require 'ripper'

module SpecSupport
  module Architecture
    # Shared analyzer used by architecture guardrails for rescue/fallback cleanup.
    module RescueGuardrailAnalyzer
      module_function

      NUMERIC_LITERAL_TAGS = %i[@int @float @rational @imaginary].freeze
      PASS_THROUGH_VAR_TAGS = %i[@ident @ivar @cvar @gvar].freeze

      # Calls that provably cannot raise Shoko::Error: their failures are raw
      # stdlib exceptions (JSON::ParserError, Errno::*, IOError). A
      # `rescue Shoko::Error` sitting directly over one of these is the R4
      # regression — the handler promises containment the class can't deliver,
      # and the real error escapes (constitution §VIII).
      PROVABLY_NON_SHOKO_CALLS = {
        'JSON.parse' => /\bJSON\.parse\b/,
        'JSON.load' => /\bJSON\.load\b/,
        'File.read' => /\bFile\.read\b/,
        'File.binread' => /\bFile\.binread\b/
      }.freeze

      def fallback_literal_rescue_offenders(lib_root:)
        rescue_default_offenses(lib_root:).map { |offense| format_rescue_default_offense(offense) }
      end

      def numeric_default_rescue_offenders(lib_root:)
        rescue_default_offenses(lib_root:)
          .select { |offense| offense[:kind] == :numeric_literal }
          .map { |offense| format_rescue_default_offense(offense) }
      end

      def no_op_reraise_rescue_offenders(lib_root:, roots: nil)
        ruby_files(lib_root:, roots:).flat_map do |path|
          rescue_nodes_for_file(path).filter_map do |rescue_node|
            next if rescue_handles_fatal_external_input?(rescue_node)

            body_stmt = first_rescue_statement(rescue_node)
            next unless bare_raise_statement?(body_stmt)

            line = expression_line(body_stmt) || 1
            "#{relative(path, lib_root)}:#{line}"
          end
        end
      end

      def swallowing_rescue_offenders(lib_root:, roots: nil)
        ruby_files(lib_root:, roots:).flat_map do |path|
          source = File.read(path)
          lines = source.lines
          rescue_nodes_for_source(source).filter_map do |rescue_node|
            statements = rescue_statements(rescue_node)
            next if statements.nil? || statements.empty?
            next if contains_raise?(statements)

            stmt = first_rescue_statement(rescue_node)
            line = expression_line(stmt || rescue_node) || 1
            snippet = lines[line - 1]&.strip.to_s
            "#{relative(path, lib_root)}:#{line} -> #{snippet}"
          end
        end
      end

      def overlapping_rescue_chain_offenders(lib_root:)
        files = ruby_files(lib_root:)
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
        files = ruby_files(lib_root:)
        pattern = /\boptional\s*\?\s*container\.resolve\(key\)\s*:\s*container\.resolve\(key\)/

        files.filter_map do |path|
          rel = relative(path, lib_root)
          next unless File.readlines(path).any? { |line| line.match?(pattern) }

          rel
        end
      end

      def standard_error_rescue_offenders(lib_root:)
        files = ruby_files(lib_root:)
        files.filter_map do |path|
          rel = relative(path, lib_root)
          next unless File.readlines(path).any? { |line| line.match?(/\brescue\s+StandardError\b/) }

          rel
        end
      end

      def standard_error_rescue_without_translation_offenders(lib_root:)
        ruby_files(lib_root:).flat_map do |path|
          lines = File.readlines(path)
          lines.each_with_index.filter_map do |line, index|
            match = line.match(/^(\s*)rescue\s+StandardError\b/)
            next unless match

            indent = match[1].size
            body = rescue_body_lines(lines, index + 1, indent)
            next if translated_standard_error_rescue?(body)

            "#{relative(path, lib_root)}:#{index + 1}"
          end
        end
      end

      # `# resilient-boundary` markers document deliberate isolation points
      # (constitution §VIII / R4). A marker on anything narrower than
      # `rescue StandardError` is exactly the regression R4 exists to prevent:
      # the comment promises containment the rescue class cannot deliver.
      def mismarked_resilient_boundary_offenders(lib_root:)
        ruby_files(lib_root:).flat_map do |path|
          lines = File.readlines(path)
          lines.each_with_index.filter_map do |line, index|
            next unless line.strip == '# resilient-boundary'

            follower = lines[index + 1]
            next if follower&.match?(/^\s*rescue\s+StandardError\b/)

            "#{relative(path, lib_root)}:#{index + 1}"
          end
        end
      end

      # Flags `rescue Shoko::Error` (a single Shoko::Error class, not combined
      # with StandardError or a stdlib class) whose own begin-block directly
      # calls something that cannot raise Shoko::Error. Only direct calls in
      # the rescued block count — no cross-method guessing — so the rule is
      # decidable and false-positive-free.
      def narrow_shoko_rescue_over_stdlib_offenders(lib_root:)
        ruby_files(lib_root:).flat_map do |path|
          lines = File.readlines(path)
          lines.each_index.filter_map do |index|
            next unless lines[index].match?(/^\s*rescue\s+Shoko::Error\b\s*(?:=>\s*\w+)?\s*\z/)

            body = shoko_rescue_block_body(lines, index)
            matched = PROVABLY_NON_SHOKO_CALLS.find do |_name, pattern|
              body.any? { |line| !line.strip.start_with?('#') && line.match?(pattern) }
            end
            next unless matched

            "#{relative(path, lib_root)}:#{index + 1} -> #{matched.first}"
          end
        end
      end

      # The lines of the begin-block guarded by the rescue at rescue_index: walk
      # up to the nearest opener (def/begin/...do) at the rescue's indent or
      # shallower, which in Ruby is where the rescued block starts.
      def shoko_rescue_block_body(lines, rescue_index)
        indent = lines[rescue_index][/^\s*/].length
        start = rescue_index
        index = rescue_index - 1
        while index >= 0
          line = lines[index]
          if line[/^\s*/].length <= indent && line.match?(/^\s*(?:def |begin\b|.*\bdo\b)/)
            start = index
            break
          end
          index -= 1
        end
        lines[start...rescue_index]
      end

      def exception_rescue_offenders(lib_root:)
        files = ruby_files(lib_root:)
        files.filter_map do |path|
          rel = relative(path, lib_root)
          next unless File.readlines(path).any? { |line| line.match?(/\brescue\s+Exception\b/) }

          rel
        end
      end

      def bare_string_raise_offenders(lib_root:)
        files = ruby_files(lib_root:)
        offenders = []

        files.each do |path|
          lines = File.readlines(path)
          lines.each_with_index do |line, index|
            next unless line.match?(/\braise\s+['"]/)

            offenders << "#{relative(path, lib_root)}:#{index + 1}"
          end
        end

        offenders
      end

      def implicit_null_runtime_config_offenders(lib_root:)
        files = ruby_files(lib_root:)
        pattern = /\|\|\s*Shoko::(?:Adapters|Shared)::Runtime::NullRuntimeConfig\.instance/
        offenders = []

        files.each do |path|
          lines = File.readlines(path)
          lines.each_with_index do |line, index|
            next unless line.match?(pattern)

            offenders << "#{relative(path, lib_root)}:#{index + 1}"
          end
        end

        offenders
      end

      def fallback_literal_count(lib_root:)
        fallback_literal_rescue_offenders(lib_root:).length
      end

      def relative(path, lib_root)
        path.delete_prefix("#{lib_root}/")
      end

      def rescue_default_offenses(lib_root:)
        ruby_files(lib_root:).flat_map do |path|
          source = File.read(path)
          lines = source.lines
          rescue_nodes_for_source(source).filter_map do |rescue_node|
            statement = first_rescue_statement(rescue_node)
            next unless statement

            kind = rescue_default_kind(statement)
            next unless kind

            line = expression_line(statement) || rescue_header_line(rescue_node) || 1
            {
              path: relative(path, lib_root),
              line: line,
              kind: kind,
              code: lines[line - 1]&.strip.to_s
            }
          end
        end
      end

      def format_rescue_default_offense(offense)
        details = offense[:code].to_s.empty? ? offense[:kind].to_s : "#{offense[:kind]} (#{offense[:code]})"
        "#{offense[:path]}:#{offense[:line]} -> #{details}"
      end

      def rescue_nodes_for_file(path)
        source = File.read(path)
        rescue_nodes_for_source(source)
      end

      def rescue_nodes_for_source(source)
        ast = Ripper.sexp(source)
        return [] unless ast

        collect_rescue_nodes(ast)
      end

      def collect_rescue_nodes(node, acc = [])
        return acc unless node.is_a?(Array)

        acc << node if node[0] == :rescue
        node.each do |child|
          collect_rescue_nodes(child, acc) if child.is_a?(Array)
        end
        acc
      end

      def rescue_statements(rescue_node)
        return nil unless rescue_node.is_a?(Array) && rescue_node[0] == :rescue

        rescue_node[3]
      end

      def first_rescue_statement(rescue_node)
        statements = rescue_statements(rescue_node)
        return nil unless statements.is_a?(Array)

        statements.find { |statement| significant_statement?(statement) }
      end

      def significant_statement?(statement)
        statement.is_a?(Array) && statement[0] != :void_stmt
      end

      def rescue_default_kind(statement)
        return nil unless statement.is_a?(Array)

        if return_statement?(statement)
          returned = return_expression(statement)
          return nil unless returned

          return rescue_default_kind(returned)
        end

        return :nil_literal if keyword_literal?(statement, 'nil')
        return :false_literal if keyword_literal?(statement, 'false')
        return :true_literal if keyword_literal?(statement, 'true')
        return :empty_array_literal if empty_array_literal?(statement)
        return :empty_hash_literal if empty_hash_literal?(statement)
        return :empty_string_literal if empty_string_literal?(statement)
        return :symbol_literal if symbol_literal?(statement)
        return :numeric_literal if numeric_literal?(statement)
        return :variable_passthrough if variable_passthrough?(statement)

        nil
      end

      def return_statement?(statement)
        statement[0] == :return
      end

      def return_expression(statement)
        args = statement[1]
        return nil unless args.is_a?(Array) && args[0] == :args_add_block

        expressions = args[1]
        return nil unless expressions.is_a?(Array)
        return nil unless expressions.length == 1

        expressions[0]
      end

      def keyword_literal?(statement, value)
        return false unless statement[0] == :var_ref

        token = statement[1]
        token.is_a?(Array) && token[0] == :@kw && token[1] == value
      end

      def empty_array_literal?(statement)
        return false unless statement[0] == :array

        body = statement[1]
        body.nil? || (body.is_a?(Array) && body.empty?)
      end

      def empty_hash_literal?(statement)
        return false unless statement[0] == :hash

        body = statement[1]
        body.nil? || (body.is_a?(Array) && body.empty?)
      end

      def empty_string_literal?(statement)
        return false unless statement[0] == :string_literal

        content = statement[1]
        return true if content == [:string_content]

        content.is_a?(Array) && content[0] == :string_content && content[1].nil?
      end

      def symbol_literal?(statement)
        statement[0] == :symbol_literal
      end

      def numeric_literal?(statement)
        return true if NUMERIC_LITERAL_TAGS.include?(statement[0])

        statement[0] == :unary && statement[1] == :-@ && numeric_literal?(statement[2])
      end

      def variable_passthrough?(statement)
        return false unless statement[0] == :var_ref

        token = statement[1]
        token.is_a?(Array) && PASS_THROUGH_VAR_TAGS.include?(token[0])
      end

      def contains_raise?(node)
        return false unless node.is_a?(Array)

        return true if bare_raise_statement?(node)
        return true if command_raise_statement?(node)

        node.any? { |child| child.is_a?(Array) && contains_raise?(child) }
      end

      def rescue_handles_fatal_external_input?(rescue_node)
        exceptions = rescue_node[1]
        return false unless exceptions

        constants = []
        collect_constant_names(exceptions, constants)
        constants.include?('FatalExternalInputError')
      end

      def collect_constant_names(node, acc)
        return acc unless node.is_a?(Array)

        acc << node[1] if node[0] == :@const
        node.each do |child|
          collect_constant_names(child, acc) if child.is_a?(Array)
        end
        acc
      end

      def bare_raise_statement?(statement)
        return false unless statement.is_a?(Array) && statement[0] == :vcall

        ident = statement[1]
        ident.is_a?(Array) && ident[0] == :@ident && ident[1] == 'raise'
      end

      def command_raise_statement?(statement)
        return false unless statement.is_a?(Array) && statement[0] == :command

        ident = statement[1]
        ident.is_a?(Array) && ident[0] == :@ident && ident[1] == 'raise'
      end

      def expression_line(node)
        return nil unless node.is_a?(Array)

        if node[0].to_s.start_with?('@') && node[2].is_a?(Array)
          return node[2][0]
        end

        node.each do |child|
          line = expression_line(child)
          return line if line
        end
        nil
      end

      def rescue_header_line(rescue_node)
        return nil unless rescue_node.is_a?(Array) && rescue_node[0] == :rescue

        expression_line(rescue_node[1]) || expression_line(rescue_node[2])
      end

      def ruby_files(lib_root:, roots: nil)
        return Dir[File.join(lib_root, '**', '*.rb')] unless roots

        Array(roots).flat_map do |root|
          Dir[File.join(root, '**', '*.rb')]
        end.uniq
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

      def rescue_body_lines(lines, start_index, indent)
        body = []
        index = start_index
        while index < lines.length
          line = lines[index]
          boundary = line.match(/^(\s*)(rescue|else|ensure|end)\b/)
          break if boundary && boundary[1].size == indent

          body << line
          index += 1
        end
        body
      end

      # A rescue StandardError branch counts as "translated" when its body
      # makes the error-handling decision explicit. The four accepted forms,
      # in order of strength:
      #
      #   1. `raise`                — re-raises the original; the rescue
      #                               narrows scope but doesn't swallow.
      #                               The `(?!\s*if\b)` guard excludes
      #                               conditional re-raise here so the
      #                               no-op-reraise guardrail still flags
      #                               bare `raise` standing alone — but
      #                               other lines in the same body (like
      #                               `raise SpecificError.new(...)`) can
      #                               still satisfy the translation rule.
      #   2. `raise_X(...)`          — escalates via a domain-specific raiser
      #                               whose name documents what's being raised.
      #   3. `return X_error(...)`   — exits the method via a typed-error
      #                               constructor, surfacing failure as a
      #                               value to the caller.
      #   4. `handle|record|translate|swallow_*_error(...)` — calls an
      #                               explicitly-named error handler. The
      #                               name shape matters: it forces the
      #                               author to name what kind of handling
      #                               is happening — `handle_` for pipeline
      #                               routing, `record_` for log/persist,
      #                               `translate_` for type conversion,
      #                               `swallow_` for deliberate best-effort
      #                               drops. Inline `@var = ...` mutations
      #                               are NOT recognized as translation;
      #                               extract them into a named handler
      #                               method using one of the four verbs
      #                               above.
      def translated_standard_error_rescue?(body_lines)
        significant = body_lines.map(&:strip).reject(&:empty?).reject { |line| line.start_with?('#') }
        return false if significant.empty?

        significant.any? do |line|
          line.match?(/\Araise\b(?!\s*if\b)/) ||
            line.match?(/\braise_[a-zA-Z0-9_!?]+\b/) ||
            line.match?(/\Areturn\s+[a-zA-Z0-9_]+_error\(/) ||
            line.match?(/\b(?:handle|record|translate|swallow)_[a-zA-Z0-9_]*error\b/)
        end
      end

      module_function :relative,
                      :rescue_default_offenses,
                      :format_rescue_default_offense,
                      :rescue_nodes_for_file,
                      :rescue_nodes_for_source,
                      :collect_rescue_nodes,
                      :rescue_statements,
                      :first_rescue_statement,
                      :significant_statement?,
                      :rescue_default_kind,
                      :return_statement?,
                      :return_expression,
                      :keyword_literal?,
                      :empty_array_literal?,
                      :empty_hash_literal?,
                      :empty_string_literal?,
                      :symbol_literal?,
                      :numeric_literal?,
                      :variable_passthrough?,
                      :contains_raise?,
                      :rescue_handles_fatal_external_input?,
                      :collect_constant_names,
                      :bare_raise_statement?,
                      :command_raise_statement?,
                      :expression_line,
                      :rescue_header_line,
                      :ruby_files,
                      :parse_rescue_header,
                      :find_next_same_indent_rescue,
                      :rescue_body_lines,
                      :translated_standard_error_rescue?,
                      :narrow_shoko_rescue_over_stdlib_offenders,
                      :shoko_rescue_block_body
    end
  end
end
