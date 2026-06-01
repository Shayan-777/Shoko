# frozen_string_literal: true

module SpecSupport
  module Architecture
    # Detects "include-once mixins": modules defined in lib that are `include`d or
    # `prepend`ed in exactly one place across the codebase. These are forbidden by
    # the architecture constitution (R1, "hard zero"): a module mixed into a single
    # host gives the indirection of decomposition with none of its benefits, and is
    # the engine of the project's refactoring churn.
    #
    # Detection is regex-based (matching the rest of the architecture spec suite)
    # and keys on the module's *short* (last) constant segment. Known limitation:
    # two distinct modules sharing a short name, each included once, are counted
    # together and therefore not flagged (a false negative, never a false positive).
    # The baseline ratchet tolerates this — it only ever tightens.
    module IncludeOnceMixinScanner
      module_function

      INCLUDE_PATTERN = /^\s*(?:include|prepend)\s+([A-Z][\w:]*)/.freeze
      MODULE_PATTERN = /^(\s*)module\s+([A-Z][\w:]*)/.freeze

      # Defining files under these prefixes are exempt: port modules legitimately
      # declare a contract and are "included once" by design.
      EXEMPT_PREFIXES = ['application/ports/'].freeze

      # Explicit, deliberately-empty escape hatch. Adding a path here is a
      # constitutional amendment and must be justified in docs/architecture/constitution.md.
      ALLOWLIST = [].freeze

      def violations(lib_root)
        files = Dir[File.join(lib_root, '**', '*.rb')]

        include_counts = Hash.new(0)
        definitions = Hash.new { |h, k| h[k] = [] }

        files.each do |path|
          rel = path.delete_prefix("#{lib_root}/")
          lines = non_comment_lines(path)
          lines.each do |line|
            include_counts[short_name(Regexp.last_match(1))] += 1 if line.match(INCLUDE_PATTERN)
          end
          innermost_modules(lines).each { |name| definitions[name] << rel }
        end

        included_once = include_counts.select { |_name, count| count == 1 }.keys

        included_once.flat_map { |name| definitions[name] }
                     .uniq
                     .reject { |rel| exempt?(rel) }
                     .sort
      end

      # The module a file actually *defines* is its innermost (deepest-indented)
      # module declaration(s). Outer module lines are namespace nesting the file
      # merely reopens; attributing an included-once *namespace* (e.g. a registration
      # module included once into the container factory) to every file that nests
      # inside it produced false positives against legitimate namespaced collaborators
      # (`Foo.build(...)`), which are never `include`d and are not R1 violations.
      def innermost_modules(lines)
        decls = lines.filter_map do |line|
          m = line.match(MODULE_PATTERN)
          [m[1].length, short_name(m[2])] if m
        end
        return [] if decls.empty?

        deepest = decls.map(&:first).max
        decls.select { |indent, _| indent == deepest }.map(&:last)
      end

      def short_name(constant)
        constant.split('::').last
      end

      def exempt?(rel)
        return true if ALLOWLIST.include?(rel)

        EXEMPT_PREFIXES.any? { |prefix| rel.start_with?(prefix) }
      end

      def non_comment_lines(path)
        File.readlines(path).reject { |line| line.strip.start_with?('#') }
      rescue StandardError
        []
      end
    end
  end
end
