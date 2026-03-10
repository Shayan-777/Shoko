# frozen_string_literal: true

require_relative '../../../../core/ports/outbound/reader_session_store'
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

            def initialize(navigation_service:, bookmark_service:, reader_session_store:)
              unless reader_session_store.is_a?(Shoko::Core::Ports::Outbound::ReaderSessionStore)
                raise ArgumentError, 'reader_session_store must implement Core::Ports::Outbound::ReaderSessionStore'
              end

              @navigation_service = navigation_service
              @bookmark_service = bookmark_service
              @reader_session_store = reader_session_store
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
              chapter = @reader_session_store.load.current_chapter
              chapter.nil? ? 0 : Integer(chapter)
            end
          end
        end
      end
    end
  end
end
