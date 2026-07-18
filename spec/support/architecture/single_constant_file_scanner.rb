# frozen_string_literal: true

require 'ripper'

module SpecSupport
  module Architecture
    # Enforces constitution §III: "a file is named after the single
    # class/module it defines."
    #
    # A file passes when every constant it defines nests under one ROOT
    # constant whose short name camelizes from the file's basename. Pure
    # namespace reopenings above the root are fine; nested helper types
    # (Data/Struct records, error classes) inside the root are fine;
    # require-only aggregator files (no definitions) are fine. Sibling
    # top-level constants sharing a file are the violation.
    #
    # Module/class ownership is indentation-based; constant assignments are
    # extracted from Ripper so qualification and line breaks cannot evade the
    # rule. The root is the shallowest definition; everything else must nest
    # strictly inside it.
    module SingleConstantFileScanner
      module_function

      DECL_PATTERN = /^(\s*)(?:module|class)\s+([A-Z][\w:]*)/.freeze
      DEF_PATTERN = /^\s*def\s/.freeze
      TYPE_CONSTRUCTORS = {
        'Struct' => 'new',
        'Data' => 'define',
        'Class' => 'new',
        'Module' => 'new',
      }.freeze

      # Codified §III exemptions — each addition is a constitutional
      # amendment (rationale in the constitution's §III/Amendments):
      ALLOWLIST = [
        # The sealed Shoko error taxonomy: one cohesive hierarchy whose 18
        # small classes form a single domain concept; eighteen three-line
        # files would be organization noise, not decomposition.
        'shared/errors.rb',
      ].freeze

      def violations(lib_root)
        Dir[File.join(lib_root, '**', '*.rb')].sort.filter_map do |path|
          rel = path.delete_prefix("#{lib_root}/")
          next if ALLOWLIST.include?(rel)

          offense = file_offense(rel, non_comment_lines(path))
          offense && "#{rel}: #{offense}"
        end
      end

      def file_offense(rel, lines)
        decls = declarations(lines)
        return nil if decls.empty?

        expected = File.basename(rel, '.rb')
        root_indent = decls.map { |d| d[:indent] }.min
        roots = decls.select { |d| d[:indent] == root_indent }

        # Walk down through pure namespace declarations: a namespace level is
        # a single module declaration that directly contains everything else.
        while roots.length == 1 && !named_after?(roots.first, rel)
          inner = decls.select { |d| d[:indent] > roots.first[:indent] }
          if inner.empty?
            # Bottom of the walk with a name mismatch. A CamelCase constant
            # assignment or a body with method definitions is a real
            # (misnamed) definition; an empty module/class body or bare
            # value constants is a namespace/values file (version.rb, route
            # tables), which §III does not govern.
            if roots.first[:has_defs] || roots.first[:kind] == :assign
              return "defines #{roots.first[:short]}, file is #{expected}.rb"
            end

            return nil
          end

          inner_min = inner.map { |d| d[:indent] }.min
          roots = inner.select { |d| d[:indent] == inner_min }
          decls = inner
        end

        if roots.length > 1
          return "sibling constants #{roots.map { |d| d[:short] }.join(', ')} (one constant per file)"
        end

        root = roots.first

        # Every remaining declaration must nest inside the root.
        stray = decls.reject { |d| d.equal?(root) || nested_inside?(d, root, decls) }
        return nil if stray.empty?

        "constants outside #{root[:short]}: #{stray.map { |d| d[:short] }.join(', ')}"
      end

      # "Named after": the constant's flattened short name must equal the
      # flattened basename, or the flattened parent-directory + basename —
      # so `cli.rb`/`CLI` and `eocd_parser.rb`/`EOCDParser` match without a
      # bespoke acronym table, and directory-scoped names like
      # `opf/navigation_selector.rb`/`OPFNavigationSelector` carry their
      # prefix in the directory. Arbitrary suffix matches (`bar.rb` defining
      # `FooBar`) do NOT pass.
      def named_after?(decl, rel)
        base_flat = File.basename(rel, '.rb').delete('_').downcase
        parent_flat = File.basename(File.dirname(rel)).delete('_').downcase
        const_flat = decl[:short].downcase

        const_flat == base_flat || const_flat == parent_flat + base_flat
      end

      # A declaration nests inside the root when it appears after the root
      # line at deeper indentation, before any subsequent declaration at or
      # above the root's level.
      def nested_inside?(decl, root, decls)
        return false if decl[:line] < root[:line]
        return false if decl[:indent] <= root[:indent]

        boundary = decls.find { |d| d[:line] > root[:line] && d[:indent] <= root[:indent] }
        boundary.nil? || decl[:line] < boundary[:line]
      end

      def declarations(lines)
        decls = constant_assignment_declarations(lines.join)
        lines.each_with_index do |line, index|
          if (m = line.match(DECL_PATTERN))
            decls << { indent: m[1].length, short: m[2].split('::').last, line: index, has_defs: false, kind: :decl }
          end
        end
        decls.sort_by! { |declaration| [declaration[:line], declaration[:indent]] }
        lines.each_with_index do |line, index|
          next unless line.match?(DEF_PATTERN)

          method_indent = line[/\A */].length
          owner = decls.reverse.find do |declaration|
            declaration[:line] < index && declaration[:indent] < method_indent
          end
          owner[:has_defs] = true if owner
        end
        decls
      end

      def constant_assignment_declarations(source)
        sexp = Ripper.sexp(source)
        return [] unless sexp

        assignments = []
        walk_assignments(sexp) do |left, right|
          token = constant_leaf(left)
          next unless token

          short = token[1]
          next unless short.match?(/[a-z]/) || type_constructor?(right)

          line, column = token[2]
          assignments << {
            indent: column, short: short, line: line - 1,
            has_defs: false, kind: :assign,
          }
        end
        assignments
      end
      private_class_method :constant_assignment_declarations

      def walk_assignments(node, &block)
        return unless node.is_a?(Array)

        yield(node[1], node[2]) if node.first == :assign
        node.each { |child| walk_assignments(child, &block) if child.is_a?(Array) }
      end
      private_class_method :walk_assignments

      def constant_leaf(node)
        return unless node.is_a?(Array)
        return node if node.first == :@const

        case node.first
        when :var_field, :const_path_field, :top_const_field
          constant_leaf(node[-1])
        end
      end
      private_class_method :constant_leaf

      def type_constructor?(node)
        call = unwrap_constructor_call(node)
        return false unless call&.first == :call

        receiver = constant_reference(call[1])
        method = call.dig(3, 1)
        receiver && TYPE_CONSTRUCTORS[receiver] == method
      end
      private_class_method :type_constructor?

      def unwrap_constructor_call(node)
        return unless node.is_a?(Array)

        case node.first
        when :method_add_arg, :method_add_block then unwrap_constructor_call(node[1])
        when :call then node
        end
      end
      private_class_method :unwrap_constructor_call

      # Only Ruby's built-in top-level constructors count. A same-named
      # qualified application constant is not assumed to construct a type.
      def constant_reference(node)
        return unless node.is_a?(Array)

        case node.first
        when :var_ref, :top_const_ref
          token = node[1]
          token[1] if token&.first == :@const
        end
      end
      private_class_method :constant_reference

      def camelize(basename)
        basename.split('_').map(&:capitalize).join
      end

      def non_comment_lines(path)
        File.readlines(path).reject { |line| line.strip.start_with?('#') }
      rescue StandardError
        []
      end
    end
  end
end
