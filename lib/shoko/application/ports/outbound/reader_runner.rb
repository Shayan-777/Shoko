# frozen_string_literal: true

module Shoko
  module Application
    module Ports
      module Outbound
        # Boundary for launching reader mode with a resolved path.
        module ReaderRunner
          def run_reader(path)
            raise NotImplementedError, "#{self.class} must implement #run_reader"
          end
        end
      end
    end
  end
end
