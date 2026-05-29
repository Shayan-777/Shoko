# frozen_string_literal: true

module Shoko
  module Application
    module Ports
      module Outbound
        # Outbound state-mutation port for the reader process/view/config slices.
        # Application use cases call this directly instead of routing state writes
        # through a *Control capability port.
        module ReaderViewMutator
          def update_reader(_attributes)
            raise NotImplementedError, "#{self.class} must implement #update_reader"
          end

          def update_config(_attributes)
            raise NotImplementedError, "#{self.class} must implement #update_config"
          end

          def update_sidebar(_attributes)
            raise NotImplementedError, "#{self.class} must implement #update_sidebar"
          end

          def toggle_view_mode
            raise NotImplementedError, "#{self.class} must implement #toggle_view_mode"
          end
        end
      end
    end
  end
end
