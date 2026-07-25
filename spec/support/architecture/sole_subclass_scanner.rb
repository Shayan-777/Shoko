# frozen_string_literal: true

require 'ripper'
require_relative 'mixin_site_extractor'
require_relative 'include_once_mixin_scanner'

module SpecSupport
  module Architecture
    # Detects R1's third door: inheritance used as behavior fragmentation.
    #
    # A class that is subclassed exactly once AND is never instantiated on its
    # own is an include-once mixin wearing a `<`. The superclass exists only to
    # be fused into the one subclass; the subclass reaches into its ivars,
    # overrides its no-op "hooks", and no caller ever sees the base type. That
    # is the same fragment indirection R1 forbids through `include`, `extend`,
    # and class reopening — with the same costs (behavior split across files,
    # a fake seam, two names for one object).
    #
    # A genuine base class is NOT flagged when it is used in its own right:
    #   * two or more subclasses — a real polymorphic family;
    #   * instantiated by name (`X.new`, or `raise X` for error taxonomies) —
    #     subclassing specializes it rather than completing it;
    #   * named as a TYPE by third parties (`rescue X`, `x.is_a?(X)`, `X ===`) —
    #     the base is the contract callers match on, which is precisely what an
    #     abstract type is for.
    #
    # Superclass expressions are Ripper-derived and resolved through Ruby's
    # lexical constant lookup — the same inventory the R1 mixin scanner uses,
    # so both doors count the same constants the same way. The "used on its
    # own" checks match conservatively on the class's short name across all of
    # lib, so a class is only ever reported when NO spelling of it is
    # constructed or type-matched anywhere.
    module SoleSubclassScanner
      module_function

      # @return [Array<String>] one line per offending superclass.
      def violations(lib_root)
        inventory = IncludeOnceMixinScanner.inventory(lib_root)
        edges = subclass_edges(lib_root, inventory)
        used = independently_used_short_names(lib_root)

        edges.filter_map do |superclass, subclasses|
          next unless subclasses.length == 1
          next if used.key?(superclass.split('::').last)

          "#{superclass} (sole subclass: #{subclasses.first})"
        end.sort
      end

      # @return [Hash{String => Array<String>}] superclass fqn => subclass fqns,
      #   restricted to superclasses that lib itself defines.
      def subclass_edges(lib_root, inventory)
        edges = Hash.new { |hash, key| hash[key] = [] }

        Dir[File.join(lib_root, '**', '*.rb')].sort.each do |path|
          InheritanceExtractor.extract(File.read(path)).each do |site|
            superclass = IncludeOnceMixinScanner.resolve(site.superclass, inventory[:definitions], inventory[:aliases])
            next unless superclass

            edges[superclass] << site.subclass
          end
        end

        edges
      end

      QUALIFIER = '(?:::)?(?:[A-Z][\\w]*::)*'

      # Short names of every constant that lib uses independently of being
      # inherited from: constructed (`X.new`, `raise X`) or named as a type
      # (`rescue X`, `is_a?(X)`, `X ===`).
      USAGE_PATTERNS = [
        /#{QUALIFIER}([A-Z][\w]*)\s*\.\s*new\b/,
        /\braise\s+#{QUALIFIER}([A-Z][\w]*)/,
        /\brescue\s+[^\n]*?#{QUALIFIER}([A-Z][\w]*)/,
        /\bis_a\?\(\s*#{QUALIFIER}([A-Z][\w]*)\s*\)/,
        /\bkind_of\?\(\s*#{QUALIFIER}([A-Z][\w]*)\s*\)/,
        /#{QUALIFIER}([A-Z][\w]*)\s*===/,
      ].freeze

      def independently_used_short_names(lib_root)
        names = {}

        Dir[File.join(lib_root, '**', '*.rb')].sort.each do |path|
          source = non_comment_source(path)
          USAGE_PATTERNS.each do |pattern|
            source.scan(pattern) { |(name)| names[name] = true }
          end
        end

        names
      end

      def non_comment_source(path)
        File.readlines(path).reject { |line| line.strip.start_with?('#') }.join
      end

      # Ripper-backed extraction of `class Sub < Super` edges, carrying the
      # lexical nesting needed to resolve the superclass expression.
      module InheritanceExtractor
        Site = Struct.new(:subclass, :superclass, keyword_init: true)

        module_function

        # @return [Array<Site>] superclass carries a MixinSiteExtractor::Site so
        #   the shared resolver can walk it through lexical lookup.
        def extract(source)
          sexp = Ripper.sexp(source)
          return [] unless sexp

          sites = []
          walk(sexp, [], sites)
          sites
        end

        def walk(node, stack, sites)
          return unless node.is_a?(Array)

          unless MixinSiteExtractor.ast_node?(node)
            node.each { |child| walk(child, stack, sites) if child.is_a?(Array) }
            return
          end

          case node.first
          when :module
            walk(node[2], stack + MixinSiteExtractor.const_segments(node[1]), sites)
          when :class
            walk_class(node, stack, sites)
          else
            node.each { |child| walk(child, stack, sites) if child.is_a?(Array) }
          end
        end

        def walk_class(node, stack, sites)
          name = MixinSiteExtractor.const_segments(node[1])
          nesting = stack + name
          record(node[2], nesting, stack, sites)
          walk(node[3], nesting, sites)
        end

        # `class << self` has no superclass node; a plain class has nil there.
        def record(superclass_node, nesting, stack, sites)
          return if superclass_node.nil?

          const, top_level = MixinSiteExtractor.const_path(superclass_node) || []
          return unless const

          sites << Site.new(
            subclass: nesting.join('::'),
            superclass: MixinSiteExtractor::Site.new(
              method: 'inherit', const: const, top_level: top_level, nesting: stack.dup, line: nil
            )
          )
        end
      end
    end
  end
end
