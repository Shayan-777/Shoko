# frozen_string_literal: true

module Shoko
  module Application
    module Ports
      module Outbound
        # Port interface for constructing named background workers.
        module BackgroundWorkerBuilder
          # @param name [String]
          # @param logger [Application::Ports::Outbound::Logging, nil]
          # @return [Application::Ports::Outbound::AsyncExecutor]
          def build(name:, logger:)
            raise NotImplementedError, "#{self.class} must implement #build"
          end
        end
      end
    end
  end
end
