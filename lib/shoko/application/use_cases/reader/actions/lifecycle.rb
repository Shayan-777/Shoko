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

            def initialize(reader_runtime:)
              @reader_runtime = reader_runtime
            end

            def call(intent, payload = nil)
              validate_payload!(intent, payload)

              case intent
              when :rebuild_pagination
                @reader_runtime.rebuild_pagination
              when :clear_pagination_cache
                @reader_runtime.clear_pagination_cache
              when :quit_to_menu
                @reader_runtime.quit_to_menu
              when :quit_application
                @reader_runtime.quit_application
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
