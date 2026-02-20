# frozen_string_literal: true

module Shoko
  module Core
    module Ports::Outbound
      # Application-facing contract for mutating transient UI loading state.
      module UiLoadingWriter
        def update_ui_loading(attrs)
          raise NotImplementedError, "#{self.class} must implement #update_ui_loading"
        end
      end
    end
  end
end
