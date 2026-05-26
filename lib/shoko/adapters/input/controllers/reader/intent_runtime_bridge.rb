# frozen_string_literal: true

require_relative '../../../../application/ports/outbound/application_exit_control'
require_relative '../../../../application/ports/outbound/reader_annotation_editor_control'
require_relative '../../../../application/ports/outbound/reader_dictionary_control'
require_relative '../../../../application/ports/outbound/reader_display_control'
require_relative '../../../../application/ports/outbound/reader_lifecycle_control'
require_relative '../../../../application/ports/outbound/reader_popup_control'
require_relative '../../../../application/ports/outbound/reader_search_control'
require_relative '../../../../shared/key_definitions'
require_relative 'intent_runtime_bridge/annotation_actions'
require_relative 'intent_runtime_bridge/dictionary_actions'
require_relative 'intent_runtime_bridge/popup_actions'
require_relative 'intent_runtime_bridge/reader_actions'
require_relative 'intent_runtime_bridge/search_actions'
require_relative 'intent_runtime_bridge/sidebar_actions'

module Shoko
  module Adapters
    module Input
      module Controllers
        module Reader
          # Aggregates the reader action ports implemented against the reader controller.
          class IntentRuntimeBridge
            include Shoko::Application::Ports::Outbound::ApplicationExitControl
            include Shoko::Application::Ports::Outbound::ReaderAnnotationEditorControl
            include Shoko::Application::Ports::Outbound::ReaderDictionaryControl
            include Shoko::Application::Ports::Outbound::ReaderDisplayControl
            include Shoko::Application::Ports::Outbound::ReaderLifecycleControl
            include Shoko::Application::Ports::Outbound::ReaderPopupControl
            include Shoko::Application::Ports::Outbound::ReaderSearchControl
            include AnnotationActions
            include DictionaryActions
            include PopupActions
            include ReaderActions
            include SearchActions
            include SidebarActions

            def initialize(reader_controller:)
              @reader_controller = reader_controller
            end

            private

            def controller
              @reader_controller
            end
          end
        end
      end
    end
  end
end
