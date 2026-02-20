# frozen_string_literal: true

module Shoko
  module Application
    module Ports
      # Application-facing contract for mutating transient UI loading state.
      module UiLoadingWriter
        def update_ui_loading(attrs)
          raise NotImplementedError, "#{self.class} must implement #update_ui_loading"
        end
      end
    end
  end
end
