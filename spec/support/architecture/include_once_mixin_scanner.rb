# frozen_string_literal: true

require_relative 'mixin_site_extractor'

module SpecSupport
  module Architecture
    # Detects "include-once mixins": modules defined in lib that are `include`d,
    # `prepend`ed, or `extend`ed in exactly one place across the codebase. These
    # are forbidden by the architecture constitution (R1, "hard zero"): a module
    # mixed into a single host gives the indirection of decomposition with none
    # of its benefits, and is the engine of the project's refactoring churn.
    # `extend` is the same mechanism through the singleton class — invisible to
    # an include-only scan, as the TextMetrics five-module split demonstrated.
    #
    # Mixin sites and definitions come from the Ripper-backed
    # MixinSiteExtractor, so multi-argument, parenthesized, multiline, and
    # `::`-anchored spellings are all seen exactly as Ruby sees them.
    # (`extend self` is the module-function idiom, not a mixin site; the
    # extractor ignores it because `self` is not a constant.)
    #
    # Counting works on FULLY-QUALIFIED module names. Short-name keying was
    # abandoned because common module names (Sidebar, Dictionary, Constants, ...)
    # collide across the tree: that produced false positives and, worse, made
    # include counts shift when an unrelated same-named module changed.
    #
    # A file is attributed only to the module(s) it actually defines — those at
    # its deepest nesting level — so namespaces the file merely reopens (and
    # legitimate `Foo.build(...)` collaborators that are never `include`d) are
    # not flagged.
    module IncludeOnceMixinScanner
      module_function

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
        include_sites = [] # [Site]

        files.each do |path|
          rel = path.delete_prefix("#{lib_root}/")
          defs, sites = MixinSiteExtractor.extract(read_source(path))
          defs.each { |definition| all_definitions[definition.segments.join('::')] = true }
          deepest = defs.map(&:depth).max
          defs.select { |definition| definition.depth == deepest }
              .each { |definition| own_definitions[definition.segments.join('::')] << rel }
          include_sites.concat(sites)
        end

        include_counts = Hash.new(0)
        include_sites.each do |site|
          fqn = resolve(site, all_definitions)
          include_counts[fqn] += 1 if fqn
        end

        include_counts.select { |_fqn, count| count == 1 }.keys
                      .flat_map { |fqn| own_definitions[fqn] }
                      .uniq
                      .reject { |rel| exempt?(rel) }
                      .sort
      end

      # Resolve a mixin site to a defined FQN, mimicking Ruby lexical lookup:
      # a `::`-anchored constant resolves only at the top level; otherwise try
      # <nesting>::const, walk outward, then the const itself (an
      # already-qualified path).
      def resolve(site, all_definitions)
        return (all_definitions[site.const] ? site.const : nil) if site.top_level

        segments = site.nesting
        (0..segments.length).to_a.reverse_each do |k|
          candidate = (segments[0...k] + [site.const]).join('::')
          return candidate if all_definitions[candidate]
        end
        nil
      end

      def exempt?(rel)
        return true if ALLOWLIST.include?(rel)

        EXEMPT_PREFIXES.any? { |prefix| rel.start_with?(prefix) }
      end

      def read_source(path)
        File.read(path)
      rescue StandardError
        ''
      end
    end
  end
end
