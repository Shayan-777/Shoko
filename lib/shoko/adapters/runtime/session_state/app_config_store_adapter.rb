# frozen_string_literal: true

require_relative '../../../core/models/session/config_snapshot'
require_relative '../../../core/ports/outbound/app_config_store'
require_relative 'branch_snapshot_support'

module Shoko
  module Adapters
    module Runtime
      module SessionState
        # Adapter-backed application config store over ObserverStateStore.
        class AppConfigStoreAdapter
          include Shoko::Core::Ports::Outbound::AppConfigStore
          include BranchSnapshotSupport

          Shoko::Core::Models::Session::ConfigSnapshotFields.each do |field|
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

            config_state = duplicate_branch(root[:config] || {})
            snapshot = Shoko::Core::Models::Session::ConfigSnapshot.from_state(config_state)
            @snapshot_root = root
            @snapshot = snapshot
            snapshot
          end

          def save(snapshot)
            unless snapshot.is_a?(Shoko::Core::Models::Session::ConfigSnapshot)
              raise ArgumentError, 'snapshot must be Core::Models::Session::ConfigSnapshot'
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
