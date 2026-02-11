# frozen_string_literal: true

require_relative '../../core/ports/process_control'

module Shoko
  module Adapters
    module Runtime
      # ProcessControl adapter backed by Kernel.exit.
      class ProcessControlAdapter
        include Shoko::Core::Ports::ProcessControl

        def terminate(code = 0)
          Kernel.exit(code)
        end
      end
    end
  end
end
