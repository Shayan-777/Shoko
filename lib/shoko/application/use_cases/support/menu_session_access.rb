# frozen_string_literal: true

require_relative '../../ports/outbound/state/menu_snapshot'
require_relative '../../ports/outbound/menu_session_store'
require_relative '../../ports/outbound/menu_transient_store'
require_relative '../../ports/outbound/state/menu_state_partition'

module Shoko
  module Application
    module UseCases
      module Support
        # Shared snapshot access helpers for menu use-cases backed by the
        # menu session and transient outbound store ports.
        module MenuSessionAccess
          private

          def assign_menu_session_store!(menu_session_store, menu_transient_store:)
            unless menu_session_store.is_a?(Shoko::Application::Ports::Outbound::MenuSessionStore)
              raise ArgumentError, 'menu_session_store must implement Application::Ports::Outbound::MenuSessionStore'
            end
            unless menu_transient_store.is_a?(Shoko::Application::Ports::Outbound::MenuTransientStore)
              raise ArgumentError, 'menu_transient_store must implement Application::Ports::Outbound::MenuTransientStore'
            end

            @menu_session_store = menu_session_store
            @menu_transient_store = menu_transient_store
          end

          def current_menu
            Shoko::Application::Ports::Outbound::State::MenuSnapshot.build(
              @menu_session_store.load.to_h.merge(@menu_transient_store.load.to_h)
            )
          end

          def update_menu(attributes = nil, **kwargs)
            payload = normalize_menu_update(attributes, kwargs)
            return current_menu if payload.empty?

            session_attributes, transient_attributes =
              Shoko::Application::Ports::Outbound::State::MenuStatePartition.split(payload)
            previous_session = @menu_session_store.load
            previous_transient = @menu_transient_store.load

            @menu_session_store.save(previous_session.with(**session_attributes)) unless session_attributes.empty?
            @menu_transient_store.save(previous_transient.with(**transient_attributes)) if transient_attributes.any?
            current_menu
          rescue Shoko::Error, ArgumentError
            rollback_menu_update(previous_session, previous_transient, session_attributes, transient_attributes)
            raise
          end

          def normalize_menu_update(attributes, kwargs)
            return kwargs if attributes.nil?
            return attributes if kwargs.empty? && attributes.is_a?(Hash)

            raise ArgumentError, 'menu updates must be provided as a Hash or keyword arguments'
          end

          def rollback_menu_update(previous_session, previous_transient, session_attributes, transient_attributes)
            @menu_session_store.save(previous_session) if previous_session && session_attributes&.any?
            return unless previous_transient && transient_attributes && !transient_attributes.empty?

            @menu_transient_store.save(previous_transient)
          rescue Shoko::Error, ArgumentError => e
            @last_menu_update_rollback_error = e
          end
        end
      end
    end
  end
end
