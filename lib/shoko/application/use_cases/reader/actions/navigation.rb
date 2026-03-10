# frozen_string_literal: true

require_relative '../../support/intent_action_group'

module Shoko
  module Application
    module UseCases
      module Reader
        module Actions
          class Navigation
            include Shoko::Application::UseCases::Support::IntentActionGroup

            SUPPORTED_INTENTS = %i[
              next_page
              prev_page
              scroll_down
              scroll_up
              next_chapter
              prev_chapter
              go_to_start
              go_to_end
              add_bookmark
            ].freeze

            def initialize(navigation_service:, bookmark_service:, reader_state_reader:)
              @navigation_service = navigation_service
              @bookmark_service = bookmark_service
              @reader_state_reader = reader_state_reader
            end

            def call(intent, payload = nil)
              validate_payload!(intent, payload)

              case intent
              when :next_page
                @navigation_service.next_page
              when :prev_page
                @navigation_service.prev_page
              when :scroll_down
                @navigation_service.scroll(:down, 1)
              when :scroll_up
                @navigation_service.scroll(:up, 1)
              when :next_chapter
                @navigation_service.jump_to_chapter(current_chapter + 1)
              when :prev_chapter
                @navigation_service.jump_to_chapter([current_chapter - 1, 0].max)
              when :go_to_start
                @navigation_service.go_to_start
              when :go_to_end
                @navigation_service.go_to_end
              when :add_bookmark
                @bookmark_service.add_bookmark(nil)
              else
                raise ArgumentError, "unsupported reader navigation intent: #{intent}"
              end

              :handled
            end

            private

            def current_chapter
              chapter = @reader_state_reader&.current_chapter
              chapter.nil? ? 0 : Integer(chapter)
            end
          end
        end
      end
    end
  end
end
