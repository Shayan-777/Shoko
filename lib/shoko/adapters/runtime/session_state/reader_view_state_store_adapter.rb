# frozen_string_literal: true

require_relative '../../../core/models/session/reader_view_state_snapshot'
require_relative '../../../application/ports/outbound/reader_view_state_store'
require_relative 'branch_snapshot_support'

module Shoko
  module Adapters
    module Runtime
      module SessionState
        # Adapter-backed reader view-state store over ObserverStateStore.
        class ReaderViewStateStoreAdapter
          include Shoko::Application::Ports::Outbound::ReaderViewStateStore
          include BranchSnapshotSupport

          LOADING_FIELDS = %i[loading_active loading_message loading_progress].freeze

          Shoko::Core::Models::Session::ReaderViewStateSnapshotFields.each do |field|
            define_method(field) do
              if LOADING_FIELDS.include?(field)
                @state.peek_at(:ui, field)
              else
                @state.peek_at(:reader, field)
              end
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

            snapshot = Shoko::Core::Models::Session::ReaderViewStateSnapshot.from_state(
              reader_state: duplicate_fields(root[:reader] || {}, view_reader_fields),
              ui_state: duplicate_fields(root[:ui] || {}, LOADING_FIELDS)
            )
            @snapshot_root = root
            @snapshot = snapshot
            snapshot
          end

          def save(snapshot)
            unless snapshot.is_a?(Shoko::Core::Models::Session::ReaderViewStateSnapshot)
              raise ArgumentError, 'snapshot must be Core::Models::Session::ReaderViewStateSnapshot'
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

          def sidebar_visible?
            sidebar_visible == true
          end

          def loading_active?
            loading_active == true
          end

          def dictionary_visible?
            dictionary_visible == true
          end

          def sidebar_toc_filter_active?
            sidebar_toc_filter_active == true
          end

          private

          def view_reader_fields
            @view_reader_fields ||= Shoko::Core::Models::Session::ReaderViewStateSnapshotFields - LOADING_FIELDS
          end
        end
      end
    end
  end
end
