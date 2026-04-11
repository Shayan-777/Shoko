# frozen_string_literal: true

require_relative '../../support/intent_action_group'
require_relative '../../support/menu_session_access'
require_relative '../../support/text_editing'
require_relative '../../requests/selection_delta'
require_relative '../../requests/text_input'
require_relative 'rss_reader/focus_flow'
require_relative 'rss_reader/selection_flow'
require_relative 'rss_reader/input_flow'
require_relative 'rss_reader/routing'

module Shoko
  module Application
    module UseCases
      module Menu
        module Actions
          # Handles in-screen RSS reader navigation, filtering, and article actions.
          class RssReader
            include Shoko::Application::UseCases::Support::IntentActionGroup
            include Shoko::Application::UseCases::Support::MenuSessionAccess
            include FocusFlow
            include SelectionFlow
            include InputFlow
            include Routing

            ALL_FEEDS_KEY = '__all__'
            FOCUS_ORDER = %i[feeds articles content].freeze
            MOVE_INTENTS = %i[rss_reader_move_up rss_reader_move_down].freeze
            TEXT_INPUT_INTENTS = %i[
              rss_reader_add_feed_insert_text
              rss_reader_filter_insert_text
            ].freeze
            SUPPORTED_INTENTS = %i[
              rss_reader_focus_left
              rss_reader_focus_right
              rss_reader_cycle_focus
              rss_reader_cycle_focus_back
              rss_reader_activate_selection
              rss_reader_move_up
              rss_reader_move_down
              rss_reader_go_top
              rss_reader_go_bottom
              rss_reader_page_down
              rss_reader_page_up
              rss_reader_sync
              rss_reader_toggle_zen
              rss_reader_show_all
              rss_reader_show_unread
              rss_reader_show_starred
              rss_reader_mark_read
              rss_reader_mark_unread
              rss_reader_mark_starred
              rss_reader_unstar
              rss_reader_open_add_feed
              rss_reader_add_feed_insert_text
              rss_reader_add_feed_backspace
              rss_reader_add_feed_delete
              rss_reader_submit_add_feed
              rss_reader_open_filter
              rss_reader_filter_insert_text
              rss_reader_filter_backspace
              rss_reader_filter_delete
              rss_reader_submit_filter
              rss_reader_remove_feed
            ].freeze

            def initialize(menu_session_store:, menu_mode_control:, rss_reader_workflow:, menu_transient_store:)
              assign_menu_session_store!(menu_session_store, menu_transient_store: menu_transient_store)
              @menu_mode_control = menu_mode_control
              @rss_reader_workflow = rss_reader_workflow
            end

            def call(intent, payload = nil)
              dispatch_route(intent, payload, routes, unsupported: 'unsupported menu rss reader intent')
            end
          end
        end
      end
    end
  end
end
