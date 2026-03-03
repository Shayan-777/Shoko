# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      module Outbound
        # Boundary for constructing book cache pipelines.
        module BookCachePipelineFactory
          def build(progress_reporter:, runtime_config:, logger:)
            raise NotImplementedError, "#{self.class} must implement #build"
          end
        end
      end
    end
  end
end
