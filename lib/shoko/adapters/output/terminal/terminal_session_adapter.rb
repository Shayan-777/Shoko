# frozen_string_literal: true

require_relative '../../../application/ports/outbound/terminal_session'

module Shoko
  module Adapters
    module Output
      module Terminal
        # Port adapter exposing terminal lifecycle operations to application services.
        class TerminalSessionAdapter
          include Shoko::Application::Ports::Outbound::TerminalSession

          def initialize(terminal_service:)
            @terminal_service = terminal_service
          end

          def setup
            @terminal_service.setup
          end

          def cleanup
            @terminal_service.cleanup
          end

          def size
            @terminal_service.size
          end
        end
      end
    end
  end
end
