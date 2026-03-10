# frozen_string_literal: true

module SpecSupport
  module Architecture
    module LayerPolicy
      module_function

      MATRIX = {
        'core' => %w[core shared].freeze,
        'application' => %w[application core shared].freeze,
        'adapters' => %w[adapters core shared].freeze,
        'composition' => %w[composition adapters application core shared].freeze,
        'shared' => %w[shared].freeze,
      }.freeze

      def allowed_targets_for(layer)
        MATRIX.fetch(layer, [])
      end

      def allows?(source_layer, target_layer)
        allowed_targets_for(source_layer).include?(target_layer)
      end
    end
  end
end
