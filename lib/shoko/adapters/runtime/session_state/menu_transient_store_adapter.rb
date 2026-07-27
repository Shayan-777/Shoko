# frozen_string_literal: true

require 'shoko/application/ports/outbound/state/menu_transient_snapshot'
require 'shoko/application/ports/outbound/menu_transient_store'
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
            @snapshot_sources = nil
          end

          def load
            root = @state.peek
            return @snapshot if @snapshot_root.equal?(root) && @snapshot

            source = root[:menu] || {}
            snapshot = build_snapshot(source)
            @snapshot_root = root
            @snapshot_sources = source
            @snapshot = snapshot
            snapshot
          end

          def save(snapshot)
            unless snapshot.is_a?(Shoko::Application::Ports::Outbound::State::MenuTransientSnapshot)
              raise ArgumentError,
                    'snapshot must be Application::Ports::Outbound::State::MenuTransientSnapshot'
            end

            updates = changed_state_updates(load, snapshot)
            @state.update(updates) unless updates.empty?
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

          private

          def build_snapshot(source)
            previous_values = @snapshot&.to_h
            values = Shoko::Application::Ports::Outbound::State::MenuTransientSnapshot::FIELDS.to_h do |field|
              [field, snapshot_field(source, previous_values, field)]
            end
            Shoko::Application::Ports::Outbound::State::MenuTransientSnapshot.from_state(values)
          end

          def snapshot_field(source, previous_values, field)
            source_value = source[field]
            return previous_values.fetch(field) if @snapshot_sources && @snapshot_sources[field].equal?(source_value)

            BranchSnapshot.duplicate_branch(source_value)
          end

          def changed_state_updates(previous, current)
            previous_fields = previous.to_h
            current.to_h.each_with_object({}) do |(field, value), updates|
              old_value = previous_fields.fetch(field)
              next if old_value.equal?(value) || old_value == value

              updates[[:menu, field]] = value
            end
          end
        end
      end
    end
  end
end
