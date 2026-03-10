# frozen_string_literal: true

require_relative '../../../core/ports/outbound/menu_session_store'

module Shoko
  module Application
    module UseCases
      module Support
        # Shared snapshot access helpers for menu use-cases backed by the core MenuSessionStore port.
        module MenuSessionAccess
          private

          def assign_menu_session_store!(menu_session_store)
            unless menu_session_store.is_a?(Shoko::Core::Ports::Outbound::MenuSessionStore)
              raise ArgumentError, 'menu_session_store must implement Core::Ports::Outbound::MenuSessionStore'
            end

            @menu_session_store = menu_session_store
          end

          def current_menu
            @menu_session_store.load
          end

          def update_menu(attributes = nil, **kwargs)
            payload = normalize_menu_update(attributes, kwargs)
            return current_menu if payload.empty?

            @menu_session_store.save(current_menu.with(**payload))
          end

          def normalize_menu_update(attributes, kwargs)
            return kwargs if attributes.nil?
            return attributes if kwargs.empty? && attributes.is_a?(Hash)

            raise ArgumentError, 'menu updates must be provided as a Hash or keyword arguments'
          end
        end
      end
    end
  end
end
