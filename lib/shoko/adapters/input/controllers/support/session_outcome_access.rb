# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module Support
          # Normalizes adapter-local session outcome handling for UI session collaborators.
          module SessionOutcomeAccess
            private

            def session_payload(result)
              return result unless session_outcome?(result)

              result.payload
            end

            def session_ok?(result)
              return result.ok if session_outcome?(result)

              !!result
            end

            def session_outcome?(result)
              result.is_a?(Shoko::Shared::Contracts::SessionOutcome)
            end
          end
        end
      end
    end
  end
end
