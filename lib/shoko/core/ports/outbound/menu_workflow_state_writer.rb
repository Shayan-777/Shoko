# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      module Outbound
        # Domain-facing writer contract for menu workflows.
        module MenuWorkflowStateWriter
          def set_download_state(attrs)
            raise NotImplementedError, "#{self.class} must implement #set_download_state"
          end

          def set_dictionary_state(attrs)
            raise NotImplementedError, "#{self.class} must implement #set_dictionary_state"
          end

          def set_annotation_state(attrs)
            raise NotImplementedError, "#{self.class} must implement #set_annotation_state"
          end

          def set_loading_state(path: nil, active: nil, progress: nil, message: nil, index: nil, mode: nil)
            raise NotImplementedError, "#{self.class} must implement #set_loading_state"
          end
        end
      end
    end
  end
end
