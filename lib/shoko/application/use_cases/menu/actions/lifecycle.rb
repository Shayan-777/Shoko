# frozen_string_literal: true

require_relative '../../support/intent_action_group'

module Shoko
  module Application
    module UseCases
      module Menu
        module Actions
          class Lifecycle
            include Shoko::Application::UseCases::Support::IntentActionGroup

            SUPPORTED_INTENTS = %i[quit_application].freeze

            def initialize(application_exit_control:)
              @application_exit_control = application_exit_control
            end

            def call(intent, payload = nil)
              validate_payload!(intent, payload)
              raise ArgumentError, "unsupported menu lifecycle intent: #{intent}" unless intent == :quit_application

              @application_exit_control.quit_application(code: 0, message: '')
              :handled
            end
          end
        end
      end
    end
  end
end
