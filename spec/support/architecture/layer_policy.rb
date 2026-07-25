# frozen_string_literal: true

module SpecSupport
  module Architecture
    # The dependency rule (constitution §I), in one place.
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
        'adapters' => %w[adapters core shared].freeze,
        'composition' => %w[composition adapters application core shared].freeze,
        'shared' => %w[shared].freeze,
      }.freeze

      # Path prefixes a source layer may depend on even when the target layer
      # as a whole is closed to it.
      PATH_EXCEPTIONS = {
        'adapters' => %w[application/ports/ application/use_cases/requests/].freeze,
      }.freeze

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
      def allows_path?(source_layer, target_path)
        return true if allows?(source_layer, target_path.split('/').first)

        exceptions_for(source_layer).any? { |prefix| target_path.start_with?(prefix) }
      end

      def exceptions_for(source_layer)
        return [] if STRICT_LAYERS.include?(source_layer)

        PATH_EXCEPTIONS.fetch(source_layer, [])
      end
    end
  end
end
