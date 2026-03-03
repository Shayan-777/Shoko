# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      module Outbound
        # Outbound contract used by application intent handlers to execute reader intents.
        module ReaderIntentExecutor
          def execute(intent_symbol:, payload: nil)
            raise NotImplementedError, "#{self.class} must implement #execute"
          end
        end
      end
    end
  end
end
