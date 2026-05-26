# frozen_string_literal: true

module Shoko
  module Application
    module Ports
      module Outbound
        # Runtime boundary for launching and managing reader transitions from menu workflows.
        module MenuReaderRuntime
          def run_reader(path:, preloaded_document:, background_worker:)
            raise NotImplementedError, "#{self.class} must implement #run_reader"
          end

          def switch_mode(mode)
            raise NotImplementedError, "#{self.class} must implement #switch_mode"
          end
        end
      end
    end
  end
end
