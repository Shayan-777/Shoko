# frozen_string_literal: true

require_relative '../../../../shared/errors'

module Shoko
  module Adapters
    module Input
      module Controllers
        module Support
          # Shared fail-fast message delivery helper for input controllers.
          module MessageNotifier
            private

            def set_message(text, duration = 2)
              notifier = @notification_service
              raise ArgumentError, 'notification_service is required for message delivery' unless notifier

              notifier.set_message(text.to_s, duration)
            rescue StandardError => e
              raise e if e.is_a?(Shoko::Error)

              raise Shoko::StateUpdateError.new(%i[reader message], e.message)
            end
          end
        end
      end
    end
  end
end
