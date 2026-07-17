# frozen_string_literal: true

require 'shoko/application/ports/outbound/state/reader_session_snapshot'
require 'shoko/application/ports/outbound/reader_session_store'
require_relative 'branch_snapshot'

module Shoko
  module Adapters
    module Runtime
      module SessionState
        # Adapter-backed reader session store over the application state store.
        class ReaderSessionStoreAdapter
          include Shoko::Application::Ports::Outbound::ReaderSessionStore

          Shoko::Application::Ports::Outbound::State::ReaderSessionSnapshot::FIELDS.each do |field|
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

            snapshot = Shoko::Application::Ports::Outbound::State::ReaderSessionSnapshot.from_state(
              BranchSnapshot.duplicate_fields(
                root[:reader] || {},
                Shoko::Application::Ports::Outbound::State::ReaderSessionSnapshot::FIELDS
              )
            )
            @snapshot_root = root
            @snapshot = snapshot
            snapshot
          end

          def save(snapshot)
            unless snapshot.is_a?(Shoko::Application::Ports::Outbound::State::ReaderSessionSnapshot)
              raise ArgumentError,
                    'snapshot must be Application::Ports::Outbound::State::ReaderSessionSnapshot'
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
