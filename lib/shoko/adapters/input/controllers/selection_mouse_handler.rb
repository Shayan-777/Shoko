# frozen_string_literal: true

require_relative '../../../core/models/selection_anchor'
require_relative 'selection_mouse_handler/dependency_access'
require_relative 'selection_mouse_handler/popup_interactions'
require_relative 'selection_mouse_handler/selection_lifecycle'

module Shoko
  module Adapters
    module Input
      module Controllers
        # Handles text selection and popup menu mouse interactions.
        # Extracted from MouseableReader to reduce class size.
        module SelectionMouseHandler
          include SelectionMouseHandlerSupport::DependencyAccess
          include SelectionMouseHandlerSupport::PopupInteractions
          include SelectionMouseHandlerSupport::SelectionLifecycle
        end
      end
    end
  end
end
