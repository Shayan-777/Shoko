# frozen_string_literal: true

module Shoko
  module Application
    module Workflows
      module Menu
        # Fail-fast dependency type check at a workflow boundary.
        #
        # The prepagination warmup and its out-of-process batch validate the
        # same injected ports the same way; one definition keeps the failure
        # message identical on both sides of the process split.
        module PortContract
          module_function

          # @raise [ArgumentError] when object does not implement port
          def contract!(object, port, name)
            return if object.is_a?(port)

            raise ArgumentError, "#{name} must implement #{port.name}"
          end
        end
      end
    end
  end
end
