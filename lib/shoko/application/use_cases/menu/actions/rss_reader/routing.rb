# frozen_string_literal: true

module Shoko
  module Application
    module UseCases
      module Menu
        module Actions
          class RssReader
            # Route and payload declarations for RSS reader intents.
            module Routing
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
end
