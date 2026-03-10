# frozen_string_literal: true

require_relative 'format_registry_bootstrap'

module Shoko
  module Bootstrap
    module RuntimeBootstrap
      # Build a deterministic runtime manifest from lib/shoko.
      module Manifest
        module_function

        LAYER_RANK = {
          'shared' => 0,
          'core' => 1,
          'application' => 2,
          'adapters' => 3,
          'bootstrap' => 4,
        }.freeze

        EXCLUDED_RELATIVE_PATHS = %w[
          shoko/bootstrap/runtime_bootstrap.rb
        ].freeze

        def features(root: File.expand_path('../../..', __dir__))
          lib_root = File.join(root, 'lib')
          shoko_root = File.join(lib_root, 'shoko')

          paths = Dir[File.join(shoko_root, '**', '*.rb')]
          features = paths.filter_map do |path|
            rel = path.delete_prefix("#{lib_root}/")
            next if excluded?(rel)

            rel.delete_suffix('.rb')
          end

          features.sort_by { |feature| sort_key(feature) }.freeze
        end

        def excluded?(relative_feature_path)
          return true if EXCLUDED_RELATIVE_PATHS.include?(relative_feature_path)
          return true if relative_feature_path.start_with?('shoko/test_support/')

          false
        end
        private_class_method :excluded?

        def sort_key(feature)
          segments = feature.split('/')
          layer = segments[1]
          [LAYER_RANK.fetch(layer, 99), feature_bias(feature), feature]
        end
        private_class_method :sort_key

        def feature_bias(feature)
          return -50 if feature.include?('/constants/')
          return -40 if feature.include?('/models/')
          return -30 if feature.include?('/ports/')
          return -20 if feature.include?('/events/')
          return -10 if feature.include?('/services/')
          return 10 if feature.include?('/components/')

          0
        end
        private_class_method :feature_bias
      end

      module_function

      def manifest_features
        @manifest_features ||= Manifest.features
      end

      def booted?
        @booted == true
      end

      def boot!
        return if booted?

        manifest_features.each { |feature| require feature }
        FormatRegistryBootstrap.register!
        @booted = true
      end
    end
  end
end
