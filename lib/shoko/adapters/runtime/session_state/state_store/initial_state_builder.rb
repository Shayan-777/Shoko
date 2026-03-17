# frozen_string_literal: true

require_relative '../../../../core/models/session/schema'

module Shoko
  module Adapters
    module Runtime
      module SessionState
        class StateStore
          # Builds the canonical initial runtime state tree.
          class InitialStateBuilder
            def initialize(terminal_capabilities:)
              @terminal_capabilities = terminal_capabilities
            end

            def build
              Shoko::Core::Models::Session::Schema.initial_runtime_state(
                terminal_capabilities: @terminal_capabilities
              )
            end
          end
        end
      end
    end
  end
end
