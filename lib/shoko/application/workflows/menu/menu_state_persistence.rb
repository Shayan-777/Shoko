# frozen_string_literal: true

require_relative '../../ports/outbound/state/menu_snapshot'
require_relative '../../ports/outbound/state/menu_state_partition'

module Shoko
  module Application
    module Workflows
      module Menu
        # Shared session/transient menu state persistence for menu workflows.
        module MenuStatePersistence
          private

          def current_menu
            Shoko::Application::Ports::Outbound::State::MenuSnapshot.from_stores(
              @menu_session_store, @menu_transient_store
            )
          end

          def persist_menu_payload(payload)
            session_attributes, transient_attributes =
              Shoko::Application::Ports::Outbound::State::MenuStatePartition.split(payload)
            previous_session = @menu_session_store.load
            previous_transient = @menu_transient_store.load

            @menu_session_store.save(previous_session.with(**session_attributes)) unless session_attributes.empty?
            @menu_transient_store.save(previous_transient.with(**transient_attributes)) if transient_attributes.any?
          rescue Shoko::Error, ArgumentError
            rollback_menu_payload(previous_session, previous_transient, session_attributes, transient_attributes)
            raise
          end

          def rollback_menu_payload(previous_session, previous_transient, session_attributes, transient_attributes)
            @menu_session_store.save(previous_session) if previous_session && session_attributes&.any?
            return unless previous_transient && transient_attributes && !transient_attributes.empty?

            @menu_transient_store.save(previous_transient)
          rescue Shoko::Error, ArgumentError => e
            @last_menu_payload_rollback_error = e
          end
        end
      end
    end
  end
end
