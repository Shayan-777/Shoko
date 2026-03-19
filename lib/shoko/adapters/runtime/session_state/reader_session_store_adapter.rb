# frozen_string_literal: true

require_relative '../../../core/models/session/reader_session_snapshot'
require_relative '../../../core/ports/outbound/reader_session_store'
require_relative 'branch_snapshot_support'

module Shoko
  module Adapters
    module Runtime
      module SessionState
        # Adapter-backed reader session store over ObserverStateStore.
        class ReaderSessionStoreAdapter
          include Shoko::Core::Ports::Outbound::ReaderSessionStore
          include BranchSnapshotSupport

          Shoko::Core::Models::Session::ReaderSessionSnapshotFields.each do |field|
            define_method(field) do
              @state.peek_at(:reader, field)
            end
          end

          def initialize(state, ui_session_registry: nil) # rubocop:disable Lint/UnusedMethodArgument
            @state = state
            @snapshot_root = nil
            @snapshot = nil
          end

          def load
            root = @state.peek
            return @snapshot if @snapshot_root.equal?(root) && @snapshot

            snapshot = Shoko::Core::Models::Session::ReaderSessionSnapshot.from_state(
              duplicate_fields(
                root[:reader] || {},
                Shoko::Core::Models::Session::ReaderSessionSnapshotFields
              )
            )
            @snapshot_root = root
            @snapshot = snapshot
            snapshot
          end

          def save(snapshot)
            unless snapshot.is_a?(Shoko::Core::Models::Session::ReaderSessionSnapshot)
              raise ArgumentError, 'snapshot must be Core::Models::Session::ReaderSessionSnapshot'
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

          def running?
            running == true
          end
        end
      end
    end
  end
end
