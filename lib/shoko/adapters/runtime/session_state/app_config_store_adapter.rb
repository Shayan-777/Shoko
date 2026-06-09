# frozen_string_literal: true

require_relative '../../../application/ports/outbound/state/config_snapshot'
require_relative '../../../application/ports/outbound/app_config_store'
require_relative 'branch_snapshot'

module Shoko
  module Adapters
    module Runtime
      module SessionState
        # Adapter-backed application config store over the application state store.
        class AppConfigStoreAdapter
          include Shoko::Application::Ports::Outbound::AppConfigStore

          Shoko::Application::Ports::Outbound::State::ConfigSnapshot::FIELDS.each do |field|
            define_method(field) do
              @state.peek_at(:config, field)
            end
          end

          def initialize(state)
            @state = state
            @snapshot_root = nil
            @snapshot = nil
          end

          def load
            root = @state.peek
            return @snapshot if @snapshot_root.equal?(root) && @snapshot

            config_state = BranchSnapshot.duplicate_branch(root[:config] || {})
            snapshot = Shoko::Application::Ports::Outbound::State::ConfigSnapshot.from_state(config_state)
            @snapshot_root = root
            @snapshot = snapshot
            snapshot
          end

          def save(snapshot)
            unless snapshot.is_a?(Shoko::Application::Ports::Outbound::State::ConfigSnapshot)
              raise ArgumentError, 'snapshot must be Application::Ports::Outbound::State::ConfigSnapshot'
            end

            @state.update(snapshot.to_state_updates)
            @state.save_config
            snapshot
          end

          def update
            raise ArgumentError, 'block required' unless block_given?

            save(yield(load))
          end

          def snapshot
            load
          end
        end
      end
    end
  end
end
