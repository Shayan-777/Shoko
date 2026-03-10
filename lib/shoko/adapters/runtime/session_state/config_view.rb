# frozen_string_literal: true

require_relative '../../../core/models/session/config_snapshot'
require_relative '../../../core/ports/outbound/app_config_store'

module Shoko
  module Adapters
    module Runtime
      module SessionState
        # Adapter-local dynamic view over the current config snapshot.
        class ConfigView
          Shoko::Core::Models::Session::ConfigSnapshotFields.each do |field|
            define_method(field) do
              current_config.to_h[field]
            end
          end

          def initialize(app_config_store:)
            unless app_config_store.is_a?(Shoko::Core::Ports::Outbound::AppConfigStore)
              raise ArgumentError, 'app_config_store must implement Core::Ports::Outbound::AppConfigStore'
            end

            @app_config_store = app_config_store
          end

          def snapshot
            current_config
          end

          private

          def current_config
            @app_config_store.load
          end
        end
      end
    end
  end
end
