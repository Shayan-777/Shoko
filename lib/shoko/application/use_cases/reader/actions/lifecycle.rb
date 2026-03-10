# frozen_string_literal: true

require_relative '../../support/intent_action_group'

module Shoko
  module Application
    module UseCases
      module Reader
        module Actions
          class Lifecycle
            include Shoko::Application::UseCases::Support::IntentActionGroup

            SUPPORTED_INTENTS = %i[
              rebuild_pagination
              clear_pagination_cache
              quit_to_menu
              quit_application
            ].freeze

            def initialize(reader_lifecycle_control:, application_exit_control:)
              @reader_lifecycle_control = reader_lifecycle_control
              @application_exit_control = application_exit_control
            end

            def call(intent, payload = nil)
              validate_payload!(intent, payload)

              case intent
              when :rebuild_pagination
                @reader_lifecycle_control.rebuild_pagination
              when :clear_pagination_cache
                @reader_lifecycle_control.clear_pagination_cache
              when :quit_to_menu
                @reader_lifecycle_control.return_to_menu
              when :quit_application
                @application_exit_control.quit_application(code: 0, message: '')
              else
                raise ArgumentError, "unsupported reader lifecycle intent: #{intent}"
              end

              :handled
            end
          end
        end
      end
    end
  end
end
