# frozen_string_literal: true

module Shoko
  module Application
    module Ports
      module Outbound
        # Boundary for launching menu or reader runtime modes.
        module AppModeRunner
          def run_reader(path:)
            raise NotImplementedError, "#{self.class} must implement #run_reader"
          end

          def run_menu
            raise NotImplementedError, "#{self.class} must implement #run_menu"
          end
        end
      end
    end
  end
end
