# frozen_string_literal: true

require_relative '../../../../core/ports/outbound/reader_session_store'
require_relative '../../support/intent_action_group'

module Shoko
  module Application
    module UseCases
      module Reader
        module Actions
          # Routes reader navigation intents to paging, scrolling, chapter, and bookmark services.
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
              dispatch_route(intent, payload, routes, unsupported: 'unsupported reader navigation intent')
            end

            private

            def routes
              @routes ||= {
                next_page: route(result: :handled) { @navigation_service.next_page },
                prev_page: route(result: :handled) { @navigation_service.prev_page },
                scroll_down: route(result: :handled) { @navigation_service.scroll(:down, 1) },
                scroll_up: route(result: :handled) { @navigation_service.scroll(:up, 1) },
                next_chapter: route(result: :handled) { jump_relative_chapter(1) },
                prev_chapter: route(result: :handled) { jump_relative_chapter(-1) },
                go_to_start: route(result: :handled) { @navigation_service.go_to_start },
                go_to_end: route(result: :handled) { @navigation_service.go_to_end },
                add_bookmark: route(result: :handled) { @bookmark_service.add_bookmark(nil) },
              }.freeze
            end

            def supported_payloads
              nil_payloads(*SUPPORTED_INTENTS)
            end

            def current_chapter
              chapter = @reader_session_store.load.current_chapter
              chapter.nil? ? 0 : Integer(chapter)
            end

            def jump_relative_chapter(delta)
              @navigation_service.jump_to_chapter([current_chapter + delta, 0].max)
            end
          end
        end
      end
    end
  end
end
