# frozen_string_literal: true

require_relative '../../../core/models/session/reader_pagination_snapshot'
require_relative '../../../core/ports/outbound/reader_pagination_store'
require_relative 'branch_snapshot_support'

module Shoko
  module Adapters
    module Runtime
      module SessionState
        # Adapter-backed reader pagination store over ObserverStateStore.
        class ReaderPaginationStoreAdapter
          include Shoko::Core::Ports::Outbound::ReaderPaginationStore
          include BranchSnapshotSupport

          Shoko::Core::Models::Session::ReaderPaginationSnapshotFields.each do |field|
            define_method(field) do
              @state.peek_at(:reader, field)
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

            snapshot = Shoko::Core::Models::Session::ReaderPaginationSnapshot.from_state(
              duplicate_fields(
                root[:reader] || {},
                Shoko::Core::Models::Session::ReaderPaginationSnapshotFields
              )
            )
            @snapshot_root = root
            @snapshot = snapshot
            snapshot
          end

          def save(snapshot)
            unless snapshot.is_a?(Shoko::Core::Models::Session::ReaderPaginationSnapshot)
              raise ArgumentError, 'snapshot must be Core::Models::Session::ReaderPaginationSnapshot'
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
        end
      end
    end
  end
end
