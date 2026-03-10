# frozen_string_literal: true

require_relative '../../../../core/ports/outbound/reader_intent_runtime'
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
          # Adapter runtime bridge used by the application reader intent handler.
          class IntentRuntimeBridge
            include Shoko::Core::Ports::Outbound::ReaderIntentRuntime
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
