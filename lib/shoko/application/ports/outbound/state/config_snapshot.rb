# frozen_string_literal: true

require_relative '../../../state/snapshot_support'
require_relative '../../../state/schema/config'

module Shoko
  module Application
    module Ports
      module Outbound
        module State
          # Port-contract snapshot for the application configuration slice.
          # Data contract for `Application::Ports::Outbound::AppConfigStore`.
          ConfigSnapshot = Shoko::Application::State::SnapshotSupport.define_snapshot(
            fields: Shoko::Application::State::Schema::Config::FIELDS,
            defaults: Shoko::Application::State::Schema::Config::BASE_DEFAULTS,
            partition: :config
          )

          ConfigSnapshot.const_set(:SCHEMA_VERSION, Shoko::Application::State::Schema::Config::SCHEMA_VERSION)
        end
      end
    end
  end
end
