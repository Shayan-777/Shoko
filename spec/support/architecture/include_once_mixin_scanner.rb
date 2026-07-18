# frozen_string_literal: true

require_relative 'mixin_site_extractor'

module SpecSupport
  module Architecture
    # Detects modules mixed into exactly one host. Direct constant arguments,
    # literal-array splats, and constant aliases are resolved through Ruby's
    # lexical lookup order. Dynamic targets are forbidden because an
    # architecture ratchet cannot honestly count what it cannot resolve.
    module IncludeOnceMixinScanner
      module_function

      EXEMPT_PREFIXES = ['application/ports/'].freeze

      ALLOWLIST = {
        'composition/container_factory/controller_composition.rb' =>
          'composition-root wiring module; its methods are bound into the root by design',
        'composition/container_factory/infrastructure_registration.rb' =>
          'composition-root registration wiring grouped on the container factory',
        'composition/container_factory/domain_application_registration.rb' =>
          'composition-root registration wiring grouped on the container factory',
        'composition/container_factory/port_and_repository_registration.rb' =>
          'composition-root registration wiring grouped on the container factory',
        'composition/container_factory/controller_composition/menu_builder.rb' =>
          'composition-root menu-controller wiring grouped on controller composition',
        'application/workflows/menu/reader_launch/contracts.rb' =>
          'runtime interface contracts validated by the reader-launch workflow',
      }.freeze

      def violations(lib_root)
        scan = inventory(lib_root)
        include_counts = Hash.new(0)
        scan[:sites].each do |record|
          fqn = resolve(record[:site], scan[:definitions], scan[:aliases])
          include_counts[fqn] += 1 if fqn
        end

        include_once = scan[:own_definitions].filter_map do |fqn, defining_files|
          next unless include_counts[fqn] == 1

          defining_files.reject { |rel| exempt?(rel) || ALLOWLIST.key?(rel) }
        end.flatten

        dynamic = scan[:dynamic_sites].map do |record|
          site = record[:site]
          line = site.line ? ":#{site.line}" : ''
          "#{record[:rel]}#{line}: dynamic #{site.method} target cannot be counted (constant targets only)"
        end

        (include_once + dynamic).sort
      end

      def inventory(lib_root)
        definitions = {}
        aliases = []
        sites = []
        dynamic_sites = []
        own_definitions = Hash.new { |hash, key| hash[key] = [] }

        Dir[File.join(lib_root, '**', '*.rb')].sort.each do |path|
          rel = path.delete_prefix("#{lib_root}/")
          defs, extracted_sites, extracted_aliases, extracted_dynamic =
            MixinSiteExtractor.extract(read_source(path))
          defs.each { |definition| definitions[definition.segments.join('::')] = true }
          deepest = defs.map(&:depth).max
          defs.select { |definition| definition.depth == deepest }.each do |definition|
            own_definitions[definition.segments.join('::')] << rel
          end
          sites.concat(extracted_sites.map { |site| { site: site, rel: rel, path: path } })
          dynamic_sites.concat(extracted_dynamic.map { |site| { site: site, rel: rel, path: path } })
          aliases.concat(extracted_aliases)
        end

        {
          definitions: definitions,
          own_definitions: own_definitions,
          aliases: aliases,
          sites: sites,
          dynamic_sites: dynamic_sites,
        }
      end

      # Resolve a site through lexical constant lookup and any statically
      # declared constant aliases. Alias cycles resolve to nil.
      def resolve(site, all_definitions, aliases = [])
        alias_map = aliases.to_h do |entry|
          [alias_fqn(entry, all_definitions), entry]
        end
        resolve_path(
          site.const, top_level: site.top_level, nesting: site.nesting,
          definitions: all_definitions, aliases: alias_map, visited: {}
        )
      end

      def resolve_path(const, top_level:, nesting:, definitions:, aliases:, visited:)
        candidates = lexical_candidates(const, top_level: top_level, nesting: nesting)
        candidates.each do |candidate|
          return candidate if definitions[candidate]

          target = aliases[candidate]
          next unless target
          next if visited[candidate]

          visited[candidate] = true
          resolved = resolve_path(
            target.target, top_level: target.target_top_level, nesting: target.nesting,
            definitions: definitions, aliases: aliases, visited: visited
          )
          return resolved if resolved
        end
        nil
      end
      private_class_method :resolve_path

      def lexical_candidates(const, top_level:, nesting:)
        return [const] if top_level

        (0..nesting.length).to_a.reverse.map do |length|
          (nesting[0...length] + [const]).join('::')
        end
      end
      private_class_method :lexical_candidates

      def alias_fqn(entry, definitions)
        return entry.name if entry.name_top_level

        name_segments = entry.name.split('::')
        return (entry.nesting + name_segments).join('::') if name_segments.length == 1

        parent = name_segments[0...-1].join('::')
        resolved_parent = lexical_candidates(parent, top_level: false, nesting: entry.nesting)
                          .find { |candidate| definitions[candidate] }
        [resolved_parent || parent, name_segments.last].join('::')
      end
      private_class_method :alias_fqn

      def exempt?(rel) = EXEMPT_PREFIXES.any? { |prefix| rel.start_with?(prefix) }

      def read_source(path) = File.read(path)
    end
  end
end
