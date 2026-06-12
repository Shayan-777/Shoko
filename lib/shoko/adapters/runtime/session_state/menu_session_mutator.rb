# frozen_string_literal: true

require 'shoko/application/ports/outbound/menu_session_store'
require 'shoko/application/ports/outbound/menu_transient_store'
require 'shoko/application/ports/outbound/state/menu_state_partition'

module Shoko
  module Adapters
    module Runtime
      module SessionState
        # Adapter-local write surface for menu snapshot updates.
        class MenuSessionMutator
          def initialize(menu_session_store:, menu_transient_store:)
            unless menu_session_store.is_a?(Shoko::Application::Ports::Outbound::MenuSessionStore)
              raise ArgumentError, 'menu_session_store must implement Application::Ports::Outbound::MenuSessionStore'
            end
            unless menu_transient_store.is_a?(Shoko::Application::Ports::Outbound::MenuTransientStore)
              raise ArgumentError, 'menu_transient_store must implement Application::Ports::Outbound::MenuTransientStore'
            end

            @menu_session_store = menu_session_store
            @menu_transient_store = menu_transient_store
          end

          def update_menu(attributes)
            persist(**attributes)
          end

          private

          def persist(**attributes)
            return if attributes.empty?

            session_attributes, transient_attributes =
              Shoko::Application::Ports::Outbound::State::MenuStatePartition.split(attributes)
            previous_session = @menu_session_store.load
            previous_transient = @menu_transient_store.load

            @menu_session_store.save(previous_session.with(**session_attributes)) unless session_attributes.empty?
            unless transient_attributes.empty?
              @menu_transient_store.save(previous_transient.with(**transient_attributes))
            end
          rescue Shoko::Error, ArgumentError
            rollback(previous_session, previous_transient, session_attributes, transient_attributes)
            raise
          end

          def rollback(previous_session, previous_transient, session_attributes, transient_attributes)
            if previous_session && session_attributes && !session_attributes.empty?
              @menu_session_store.save(previous_session)
            end
            return unless previous_transient && transient_attributes && !transient_attributes.empty?

            @menu_transient_store.save(previous_transient)
          rescue Shoko::Error, ArgumentError => e
            @last_menu_rollback_error = e
          end
        end
      end
    end
  end
end
