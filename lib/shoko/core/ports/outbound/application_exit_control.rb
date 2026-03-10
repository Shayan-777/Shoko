# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      module Outbound
        # Capability port for terminating the application from application use-cases.
        module ApplicationExitControl
          def quit_application(code:, message:)
            raise NotImplementedError, "#{self.class} must implement #quit_application"
          end
        end
      end
    end
  end
end
