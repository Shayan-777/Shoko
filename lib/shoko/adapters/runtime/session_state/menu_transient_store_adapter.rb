# frozen_string_literal: true

require_relative '../../../application/ports/outbound/state/menu_transient_snapshot'
require_relative '../../../application/ports/outbound/menu_transient_store'
require_relative 'branch_snapshot'

module Shoko
  module Adapters
    module Runtime
      module SessionState
        # Adapter-backed menu transient store over the application state store.
        class MenuTransientStoreAdapter
          include Shoko::Application::Ports::Outbound::MenuTransientStore

          Shoko::Application::Ports::Outbound::State::MenuTransientSnapshot::FIELDS.each do |field|
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

            snapshot = Shoko::Application::Ports::Outbound::State::MenuTransientSnapshot.from_state(
              BranchSnapshot.duplicate_fields(
                root[:menu] || {},
                Shoko::Application::Ports::Outbound::State::MenuTransientSnapshot::FIELDS
              )
            )
            @snapshot_root = root
            @snapshot = snapshot
            snapshot
          end

          def save(snapshot)
            unless snapshot.is_a?(Shoko::Application::Ports::Outbound::State::MenuTransientSnapshot)
              raise ArgumentError,
                    'snapshot must be Application::Ports::Outbound::State::MenuTransientSnapshot'
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
