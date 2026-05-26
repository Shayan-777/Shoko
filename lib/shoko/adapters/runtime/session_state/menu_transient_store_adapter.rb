# frozen_string_literal: true

require_relative '../../../core/models/session/menu_transient_snapshot'
require_relative '../../../application/ports/outbound/menu_transient_store'
require_relative 'branch_snapshot_support'

module Shoko
  module Adapters
    module Runtime
      module SessionState
        # Adapter-backed menu transient store over ObserverStateStore.
        class MenuTransientStoreAdapter
          include Shoko::Application::Ports::Outbound::MenuTransientStore
          include BranchSnapshotSupport

          Shoko::Core::Models::Session::MenuTransientSnapshotFields.each do |field|
            define_method(field) do
              @state.peek_at(:menu, field)
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

            snapshot = Shoko::Core::Models::Session::MenuTransientSnapshot.from_state(
              duplicate_fields(
                root[:menu] || {},
                Shoko::Core::Models::Session::MenuTransientSnapshotFields
              )
            )
            @snapshot_root = root
            @snapshot = snapshot
            snapshot
          end

          def save(snapshot)
            unless snapshot.is_a?(Shoko::Core::Models::Session::MenuTransientSnapshot)
              raise ArgumentError, 'snapshot must be Core::Models::Session::MenuTransientSnapshot'
            end

            @state.update(snapshot.to_state_updates)
            snapshot
          end

          def update
            raise ArgumentError, 'block required' unless block_given?

            save(yield(load))
          end

          def snapshot
            load
          end

          def loading_active?
            loading_active == true
          end

          def dictionary_entries
            Array(dictionary_results)
          end
        end
      end
    end
  end
end
