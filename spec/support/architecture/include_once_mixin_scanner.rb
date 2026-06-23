# frozen_string_literal: true

module SpecSupport
  module Architecture
    # Detects "include-once mixins": modules defined in lib that are `include`d or
    # `prepend`ed in exactly one place across the codebase. These are forbidden by
    # the architecture constitution (R1, "hard zero"): a module mixed into a single
    # host gives the indirection of decomposition with none of its benefits, and is
    # the engine of the project's refactoring churn.
    #
    # Detection is regex-based (matching the rest of the architecture spec suite) but
    # works on FULLY-QUALIFIED module names, derived from an indentation-based nesting
    # stack. Short-name keying was abandoned because common module names (Sidebar,
    # Dictionary, Constants, ...) collide across the tree: that produced false positives
    # and, worse, made include counts shift when an unrelated same-named module changed.
    #
    # A file is attributed only to the module(s) it actually defines — those at its
    # deepest nesting level — so namespaces the file merely reopens (and legitimate
    # `Foo.build(...)` collaborators that are never `include`d) are not flagged.
    module IncludeOnceMixinScanner
      module_function

      DECL_PATTERN = /^(\s*)(?:module|class)\s+([A-Z][\w:]*)/.freeze
      INCLUDE_PATTERN = /^(\s*)(?:include|prepend)\s+([A-Z][\w:]*)/.freeze

      # Defining files under these prefixes are exempt: port modules legitimately
      # declare a contract and are "included once" by design.
      EXEMPT_PREFIXES = ['application/ports/'].freeze

      # Explicit escape hatch. Adding a path here is a constitutional amendment.
      ALLOWLIST = [
        # Composition-root wiring modules. Constitution §IV explicitly endorses the
        # composition root as "a few longer, boring wiring files" included once into the
        # container factory to group registration/builder wiring — this is intentional
        # organization of the DI graph, NOT the intra-adapter single-use-mixin churn that
        # R1 targets. Each is a flat, single-responsibility wiring file.
        'composition/container_factory/infrastructure_registration.rb',
        'composition/container_factory/port_and_repository_registration.rb',
        'composition/container_factory/domain_application_registration.rb',
        'composition/container_factory/controller_composition.rb',
        'composition/container_factory/controller_composition/menu_builder.rb',
        # reader_launch/contracts defines typed interface contracts (PathResolution,
        # DocumentPreparation, ...) that implementers include AND ReaderLaunchService checks
        # via is_a? during dependency validation. They are interface/type markers — the same
        # legitimate role as application/ports (which are already exempt) — not behavior mixins.
        'application/workflows/menu/reader_launch/contracts.rb',
      ].freeze

      def violations(lib_root)
        files = Dir[File.join(lib_root, '**', '*.rb')]

        all_definitions = {} # fqn => true (every module/class defined anywhere)
        own_definitions = Hash.new { |h, k| h[k] = [] } # fqn => [files defining it at their deepest level]
        include_sites = [] # [arg, enclosing_nesting_fqn]

        files.each do |path|
          rel = path.delete_prefix("#{lib_root}/")
          defs, includes = parse(non_comment_lines(path))
          defs.each { |_indent, fqn| all_definitions[fqn] = true }
          deepest = defs.map(&:first).max
          defs.select { |indent, _| indent == deepest }.each { |_i, fqn| own_definitions[fqn] << rel }
          includes.each { |arg, nesting| include_sites << [arg, nesting] }
        end

        include_counts = Hash.new(0)
        include_sites.each do |arg, nesting|
          fqn = resolve(arg, nesting, all_definitions)
          include_counts[fqn] += 1 if fqn
        end

        include_counts.select { |_fqn, count| count == 1 }.keys
                      .flat_map { |fqn| own_definitions[fqn] }
                      .uniq
                      .reject { |rel| exempt?(rel) }
                      .sort
      end

      # Build, from one file's lines, the list of [indent, fqn] declarations and the list
      # of [include_arg, enclosing_fqn] include sites, using indentation to track nesting.
      def parse(lines)
        stack = [] # [name, indent]
        defs = []
        includes = []
        lines.each do |line|
          if (m = line.match(DECL_PATTERN))
            indent = m[1].length
            stack.pop while stack.any? && stack.last[1] >= indent
            fqn = (stack.map(&:first) + [m[2]]).join('::')
            defs << [indent, fqn]
            stack.push([m[2], indent])
          elsif (m = line.match(INCLUDE_PATTERN))
            indent = m[1].length
            enclosing = stack.reject { |_n, i| i >= indent }.map(&:first)
            includes << [m[2], enclosing.join('::')]
          end
        end
        [defs, includes]
      end

      # Resolve an include argument to a defined FQN, mimicking Ruby lexical lookup:
      # try <nesting>::arg, then walk outward, then arg itself (already-qualified path).
      def resolve(arg, nesting, all_definitions)
        segments = nesting.empty? ? [] : nesting.split('::')
        (0..segments.length).to_a.reverse_each do |k|
          candidate = (segments[0...k] + [arg]).join('::')
          return candidate if all_definitions[candidate]
        end
        nil
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
