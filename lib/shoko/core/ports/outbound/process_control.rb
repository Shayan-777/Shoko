# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      # Port for process-level control (termination).
      module ProcessControl
        def terminate(code = 0)
          raise NotImplementedError, "#{self.class} must implement #terminate"
        end
      end
    end
  end
end
