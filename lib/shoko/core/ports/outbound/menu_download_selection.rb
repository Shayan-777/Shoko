# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      module Outbound
        # Capability port for reading the active menu download selection.
        module MenuDownloadSelection
          def selected_download_result
            raise NotImplementedError, "#{self.class} must implement #selected_download_result"
          end
        end
      end
    end
  end
end
