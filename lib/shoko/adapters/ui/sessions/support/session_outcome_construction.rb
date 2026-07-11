# frozen_string_literal: true

require 'shoko/shared/contracts/session_outcome'

module Shoko
  module Adapters
    module Ui
      module Sessions
        module Support
          # Shared outcome/logging helpers for adapter-owned UI sessions.
          module SessionOutcomeConstruction
            RESCUABLE_ERRORS = [ArgumentError, TypeError, RuntimeError].freeze

            private

            def success_outcome(status, code, payload: nil)
              Shoko::Shared::Contracts::SessionOutcome.success(status: status, code: code, payload: payload)
            end

            def failure_outcome(status, code, message, payload: nil)
              Shoko::Shared::Contracts::SessionOutcome.failure(
                status: status,
                code: code,
                message: message,
                payload: payload
              )
            end

            def log_error(event, error)
              @logger&.error(event, error: error.class.name, message: error.message)
            end
          end
        end
      end
    end
  end
end
