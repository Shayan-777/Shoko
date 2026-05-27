# frozen_string_literal: true

require_relative '../../../application/ports/outbound/state/reader_pagination_snapshot'
require_relative '../../../application/ports/outbound/reader_pagination_store'
require_relative 'branch_snapshot_support'

module Shoko
  module Adapters
    module Runtime
      module SessionState
        # Adapter-backed reader pagination store over the application state store.
        class ReaderPaginationStoreAdapter
          include Shoko::Application::Ports::Outbound::ReaderPaginationStore
          include BranchSnapshotSupport

          Shoko::Application::Ports::Outbound::State::ReaderPaginationSnapshot::FIELDS.each do |field|
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

            snapshot = Shoko::Application::Ports::Outbound::State::ReaderPaginationSnapshot.from_state(
              duplicate_fields(
                root[:reader] || {},
                Shoko::Application::Ports::Outbound::State::ReaderPaginationSnapshot::FIELDS
              )
            )
            @snapshot_root = root
            @snapshot = snapshot
            snapshot
          end

          def save(snapshot)
            unless snapshot.is_a?(Shoko::Application::Ports::Outbound::State::ReaderPaginationSnapshot)
              raise ArgumentError,
                    'snapshot must be Application::Ports::Outbound::State::ReaderPaginationSnapshot'
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
