# frozen_string_literal: true

module SpecSupport
  module Architecture
    # The dependency rule (constitution section 1), in one place.
    #
    # `MATRIX` lists whole layers a source layer may depend on. The adapters
    # row deliberately omits `application`: an adapter reaches the application
    # layer ONLY through its published surface — the ports it implements and
    # the request objects it passes — never through use cases, services,
    # workflows, or state. That narrower permission is `PATH_EXCEPTIONS`
    # rather than a blanket layer edge, so the enforcement matches the rule
    # instead of being re-derived at each call site.
    module LayerPolicy
      module_function

      MATRIX = {
        'core' => %w[core shared].freeze,
        'application' => %w[application core shared].freeze,
        'adapters' => %w[core shared].freeze,
        'composition' => %w[composition adapters application core shared].freeze,
        'shared' => %w[shared].freeze,
      }.freeze

      # Path prefixes a source layer may depend on even when the target layer
      # as a whole is closed to it.
      PATH_EXCEPTIONS = {
        'adapters' => %w[application/ports/ application/use_cases/requests/].freeze,
      }.freeze

      # Adapter families are independent edge implementations. They may use
      # their own files plus this deliberately small adapter-internal shared
      # surface; sibling families are wired together only by composition.
      ADAPTER_SHARED_PATHS = %w[adapters/base_adapter.rb adapters/support/].freeze

      # Core is held to a stricter rule than the matrix implies: it depends on
      # method shape, never on an application-owned type — not even a port.
      STRICT_LAYERS = %w[core shared].freeze

      def allowed_targets_for(layer)
        MATRIX.fetch(layer, [])
      end

      def allows?(source_layer, target_layer)
        allowed_targets_for(source_layer).include?(target_layer)
      end

      # @param source_layer [String] e.g. "adapters"
      # @param target_path [String] lib-relative path, e.g. "application/ports/outbound/clock.rb"
      # @return [Boolean] true when the dependency is permitted
      def allows_path?(source_layer, target_path, source_path: nil)
        if source_layer == 'adapters' && target_path.start_with?('adapters/')
          return allows_adapter_dependency?(source_path, target_path)
        end
        return true if allows?(source_layer, target_path.split('/').first)

        exceptions_for(source_layer).any? { |prefix| target_path.start_with?(prefix) }
      end

      def exceptions_for(source_layer)
        return [] if STRICT_LAYERS.include?(source_layer)

        PATH_EXCEPTIONS.fetch(source_layer, [])
      end

      def allows_adapter_dependency?(source_path, target_path)
        return true if ADAPTER_SHARED_PATHS.any? { |path| target_path.start_with?(path) }

        source_family = adapter_family(source_path)
        target_family = adapter_family(target_path)
        !source_family.nil? && source_family == target_family
      end

      def adapter_family(path)
        match = path.to_s.match(%r{\Aadapters/([^/]+)/})
        match && match[1]
      end
    end
  end
end
