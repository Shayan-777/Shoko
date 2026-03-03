# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      module Inbound
        # Context contract for command bus intent dispatch.
        module IntentDispatchContext
          def intent_handler
            raise NotImplementedError, "#{self.class} must implement #intent_handler"
          end

          def command_bus
            raise NotImplementedError, "#{self.class} must implement #command_bus"
          end

          def command_logger
            raise NotImplementedError, "#{self.class} must implement #command_logger"
          end
        end
      end
    end
  end
end
