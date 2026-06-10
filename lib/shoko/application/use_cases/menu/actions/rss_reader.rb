# frozen_string_literal: true

require_relative '../../support/intent_action_group'
require_relative '../../support/menu_session_access'
require_relative '../../support/text_editing'
require_relative '../../requests/selection_delta'
require_relative '../../requests/edit_op'

module Shoko
  module Application
    module UseCases
      module Menu
        module Actions
          # Handles in-screen RSS reader navigation, filtering, and article actions.
          class RssReader
            include Shoko::Application::UseCases::Support::IntentActionGroup
            include Shoko::Application::UseCases::Support::MenuSessionAccess

            ALL_FEEDS_KEY = '__all__'
            FOCUS_ORDER = %i[feeds articles content].freeze
            MOVE_INTENTS = %i[rss_reader_move_up rss_reader_move_down].freeze
            EDIT_OP_INTENTS = %i[
              edit_rss_feed_input
              edit_rss_filter
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
              edit_rss_feed_input
              rss_reader_submit_add_feed
              rss_reader_open_filter
              edit_rss_filter
              rss_reader_submit_filter
              rss_reader_remove_feed
            ].freeze

            def initialize(menu_session_store:, rss_reader_workflow:, menu_transient_store:)
              assign_menu_session_store!(menu_session_store, menu_transient_store: menu_transient_store)
              @rss_reader_workflow = rss_reader_workflow
            end

            def call(intent, payload = nil)
              dispatch_route(intent, payload, routes, unsupported: 'unsupported menu rss reader intent')
            end

            PAYLOAD_FREE_INTENTS = %i[
              rss_reader_focus_left
              rss_reader_focus_right
              rss_reader_cycle_focus
              rss_reader_cycle_focus_back
              rss_reader_activate_selection
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
              rss_reader_submit_add_feed
              rss_reader_open_filter
              rss_reader_submit_filter
              rss_reader_remove_feed
            ].freeze

            private

            def move_focus(delta)
              current_index = FOCUS_ORDER.index(normalized_focus) || 0
              next_index = (current_index + delta) % FOCUS_ORDER.length
              update_menu(rss_focus: FOCUS_ORDER[next_index])
            end

            def activate_selection
              case normalized_focus
              when :feeds
                update_menu(rss_focus: :articles, rss_content_scroll: 0)
              when :articles
                article = selected_article
                return unless article

                update_menu(rss_focus: :content, rss_content_scroll: 0)
                update_selected_article_read(true) unless article[:read] == true
              when :content
                update_menu(rss_focus: :feeds)
              end
            end

            def normalized_focus
              focus = current_menu.rss_focus&.to_sym
              FOCUS_ORDER.include?(focus) ? focus : :feeds
            end

            def rss_feeds
              Array(current_menu.rss_feeds)
            end

            def rss_articles
              Array(current_menu.rss_articles)
            end

            def current_feed_index
              preferred = current_menu.rss_selected_feed_key.to_s
              rss_feeds.index { |feed| feed[:key].to_s == preferred } || 0
            end

            def current_article_index
              preferred = current_menu.rss_selected_article_id.to_s
              rss_articles.index { |article| article[:id].to_s == preferred } || 0
            end

            def selected_article
              rss_articles[current_article_index]
            end

            def move_cursor(delta)
              case normalized_focus
              when :feeds
                move_feed_selection(delta)
              when :articles
                move_article_selection(delta)
              when :content
                scroll_content(delta)
              end
            end

            def page_move(direction)
              case normalized_focus
              when :feeds
                move_feed_selection(direction * 6)
              when :articles
                move_article_selection(direction * 8)
              when :content
                scroll_content(direction * 12)
              end
            end

            def move_to_boundary(boundary)
              return move_feed_to_boundary(boundary) if normalized_focus == :feeds
              return move_article_to_boundary(boundary) if normalized_focus == :articles

              move_content_to_boundary(boundary)
            end

            def move_feed_selection(delta)
              return if rss_feeds.empty?

              current_index = current_feed_index
              next_index = (current_index + delta).clamp(0, rss_feeds.length - 1)
              select_feed(rss_feeds[next_index][:key])
            end

            def move_article_selection(delta)
              return if rss_articles.empty?

              current_index = current_article_index
              next_index = (current_index + delta).clamp(0, rss_articles.length - 1)
              select_article(rss_articles[next_index][:id])
            end

            def select_feed(feed_key)
              return if feed_key.to_s.strip.empty?

              @rss_reader_workflow.refresh_rss_reader(
                preferred_feed_key: feed_key,
                preferred_article_id: nil,
                reset_content: true
              )
            end

            def select_article(article_id)
              return if article_id.to_s.strip.empty?

              update_menu(rss_selected_article_id: article_id.to_s, rss_content_scroll: 0)
            end

            def scroll_content(delta)
              next_value = (current_menu.rss_content_scroll || 0).to_i + delta.to_i
              update_menu(rss_content_scroll: [next_value, 0].max)
            end

            def update_scope(scope)
              update_menu(rss_scope: scope)
              @rss_reader_workflow.refresh_rss_reader(reset_content: true)
            end

            def toggle_zen_mode
              next_zen_mode = current_menu.rss_zen_mode != true
              payload = { rss_zen_mode: next_zen_mode }

              if next_zen_mode
                article = selected_article || rss_articles.first
                payload[:rss_focus] = :content
                payload[:rss_selected_article_id] = article[:id] if article
              elsif normalized_focus == :content
                payload[:rss_focus] = :articles
              end

              update_menu(payload)
            end

            def update_selected_article_read(read)
              article = selected_article
              return unless article

              @rss_reader_workflow.set_rss_article_read(article[:id], read: read)
            end

            def update_selected_article_starred(starred)
              article = selected_article
              return unless article

              @rss_reader_workflow.set_rss_article_starred(article[:id], starred: starred)
            end

            def remove_selected_feed
              @rss_reader_workflow.remove_rss_feed(current_menu.rss_selected_feed_key)
            end

            def move_feed_to_boundary(boundary)
              target = boundary == :top ? rss_feeds.first : rss_feeds.last
              select_feed(target && target[:key])
            end

            def move_article_to_boundary(boundary)
              target = boundary == :top ? rss_articles.first : rss_articles.last
              select_article(target && target[:id])
            end

            def move_content_to_boundary(boundary)
              update_menu(rss_content_scroll: boundary == :top ? 0 : 100_000)
            end

            def open_add_feed_mode
              input = current_menu.rss_feed_input.to_s
              update_menu(mode: :rss_reader_feed_input, rss_feed_input_cursor: input.length)
            end

            def update_feed_input(operation, text = nil)
              next_text, next_cursor = apply_text_edit(
                current_menu.rss_feed_input,
                current_menu.rss_feed_input_cursor,
                operation,
                text: text
              )
              update_menu(rss_feed_input: next_text, rss_feed_input_cursor: next_cursor)
            end

            def submit_add_feed
              url = current_menu.rss_feed_input.to_s.strip
              if url.empty?
                update_menu(rss_status: :error, rss_message: 'Feed URL is required')
                return
              end

              @rss_reader_workflow.add_rss_feed(url)
              return if current_menu.rss_status == :error

              update_menu(mode: :rss_reader, rss_feed_input: '', rss_feed_input_cursor: 0)
            end

            def open_filter_mode
              query = current_menu.rss_filter_query.to_s
              update_menu(mode: :rss_reader_filter, rss_filter_cursor: query.length)
            end

            def update_filter_query(operation, text = nil)
              next_text, next_cursor = apply_text_edit(
                current_menu.rss_filter_query,
                current_menu.rss_filter_cursor,
                operation,
                text: text
              )
              update_menu(rss_filter_query: next_text, rss_filter_cursor: next_cursor)
              @rss_reader_workflow.refresh_rss_reader(reset_content: true)
            end

            def submit_filter
              update_menu(mode: :rss_reader)
              @rss_reader_workflow.refresh_rss_reader(reset_content: true)
            end

            def apply_text_edit(current_text, cursor, operation, text: nil)
              Shoko::Application::UseCases::Support::TextEditing.apply_edit(
                current_text.to_s,
                cursor.to_i,
                operation,
                text: text
              )
            end

            def routes
              @routes ||= focus_routes
                          .merge(selection_routes)
                          .merge(scope_routes)
                          .merge(article_routes)
                          .merge(input_routes)
                          .freeze
            end

            def supported_payloads
              nil_payloads(*PAYLOAD_FREE_INTENTS)
                .merge(delta_payloads(*MOVE_INTENTS))
                .merge(edit_op_payloads(*EDIT_OP_INTENTS))
            end

            def focus_routes
              {
                rss_reader_focus_left: route(result: :handled) { move_focus(-1) },
                rss_reader_focus_right: route(result: :handled) { move_focus(1) },
                rss_reader_cycle_focus: route(result: :handled) { move_focus(1) },
                rss_reader_cycle_focus_back: route(result: :handled) { move_focus(-1) },
                rss_reader_activate_selection: route(result: :handled) { activate_selection },
              }
            end

            def selection_routes
              handled_routes(*MOVE_INTENTS, payload: :delta) { |delta| move_cursor(delta) }.merge(
                rss_reader_go_top: route(result: :handled) { move_to_boundary(:top) },
                rss_reader_go_bottom: route(result: :handled) { move_to_boundary(:bottom) },
                rss_reader_page_down: route(result: :handled) { page_move(1) },
                rss_reader_page_up: route(result: :handled) { page_move(-1) }
              )
            end

            def scope_routes
              {
                rss_reader_show_all: route(result: :handled) { update_scope(:all) },
                rss_reader_show_unread: route(result: :handled) { update_scope(:unread) },
                rss_reader_show_starred: route(result: :handled) { update_scope(:starred) },
              }
            end

            def article_routes
              {
                rss_reader_sync: route(result: :handled) { @rss_reader_workflow.sync_rss_feeds },
                rss_reader_toggle_zen: route(result: :handled) { toggle_zen_mode },
                rss_reader_mark_read: route(result: :handled) { update_selected_article_read(true) },
                rss_reader_mark_unread: route(result: :handled) { update_selected_article_read(false) },
                rss_reader_mark_starred: route(result: :handled) { update_selected_article_starred(true) },
                rss_reader_unstar: route(result: :handled) { update_selected_article_starred(false) },
                rss_reader_remove_feed: route(result: :handled) { remove_selected_feed },
              }
            end

            def input_routes
              feed_input_routes.merge(filter_input_routes)
            end

            def feed_input_routes
              {
                rss_reader_open_add_feed: route(result: :handled) { open_add_feed_mode },
                edit_rss_feed_input: route(payload: :edit_op, result: :handled) do |op|
                  update_feed_input(op.operation, op.text)
                end,
                rss_reader_submit_add_feed: route(result: :handled) { submit_add_feed },
              }
            end

            def filter_input_routes
              {
                rss_reader_open_filter: route(result: :handled) { open_filter_mode },
                edit_rss_filter: route(payload: :edit_op, result: :handled) do |op|
                  update_filter_query(op.operation, op.text)
                end,
                rss_reader_submit_filter: route(result: :handled) { submit_filter },
              }
            end
          end
        end
      end
    end
  end
end
