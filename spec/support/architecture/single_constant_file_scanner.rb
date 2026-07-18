# frozen_string_literal: true

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
    # Detection is regex/indentation-based, matching the other architecture
    # scanners: `module`/`class` declarations plus CONST = Struct.new /
    # Data.define / Class.new / Module.new assignments, tracked on a nesting
    # stack. The root is the shallowest definition; everything else must
    # nest strictly inside it.
    module SingleConstantFileScanner
      module_function

      DECL_PATTERN = /^(\s*)(?:module|class)\s+([A-Z][\w:]*)/.freeze
      # CamelCase constant assignment (contains a lowercase letter): defines
      # a type or alias (`Foo = Struct.new`, `Snapshot = factory(...)`,
      # `TextMetrics = Shared::TextMetrics`). SCREAMING_SNAKE value constants
      # are not definitions and are ignored — EXCEPT when the right-hand side
      # is a type constructor: `URL = Data.define(:value)` defines a class no
      # matter how the constant is cased.
      ASSIGN_PATTERN = /^(\s*)([A-Z][A-Za-z0-9]*[a-z][A-Za-z0-9]*)\s*=\s*\S/.freeze
      TYPE_ASSIGN_PATTERN = /^(\s*)([A-Z][A-Za-z0-9_]*)\s*=\s*(?:Struct\.new|Data\.define|Class\.new|Module\.new)/.freeze
      DEF_PATTERN = /^\s*def\s/.freeze

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
        decls = []
        lines.each_with_index do |line, index|
          if (m = line.match(DECL_PATTERN))
            decls << { indent: m[1].length, short: m[2].split('::').last, line: index, has_defs: false, kind: :decl }
          elsif (m = line.match(TYPE_ASSIGN_PATTERN) || line.match(ASSIGN_PATTERN))
            decls << { indent: m[1].length, short: m[2], line: index, has_defs: false, kind: :assign }
          elsif line.match?(DEF_PATTERN) && (owner = decls.reverse.find { |d| d[:indent] < line[/\A */].length })
            owner[:has_defs] = true
          end
        end
        decls
      end

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
