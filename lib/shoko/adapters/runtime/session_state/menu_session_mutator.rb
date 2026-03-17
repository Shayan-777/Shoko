# frozen_string_literal: true

require_relative '../../../core/ports/outbound/menu_session_store'

module Shoko
  module Adapters
    module Runtime
      module SessionState
        # Adapter-local write surface for menu snapshot updates.
        class MenuSessionMutator
          def initialize(menu_session_store:)
            unless menu_session_store.is_a?(Shoko::Core::Ports::Outbound::MenuSessionStore)
              raise ArgumentError, 'menu_session_store must implement Core::Ports::Outbound::MenuSessionStore'
            end

            @menu_session_store = menu_session_store
          end

          def update_menu(attributes)
            persist(**attributes)
          end

          private

          def persist(**attributes)
            return if attributes.empty?

            snapshot = @menu_session_store.load
            @menu_session_store.save(snapshot.with(**attributes))
          end
        end
      end
    end
  end
end
