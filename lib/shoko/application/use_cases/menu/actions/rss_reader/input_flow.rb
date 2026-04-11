# frozen_string_literal: true

module Shoko
  module Application
    module UseCases
      module Menu
        module Actions
          class RssReader
            # Shared feed-input and filter-input helpers for RSS actions.
            module InputFlow
              private

              def open_add_feed_mode
                input = current_menu.rss_feed_input.to_s
                update_menu(mode: :rss_reader_feed_input, rss_feed_input_cursor: input.length)
                @menu_mode_control.activate_menu_mode(:rss_reader_feed_input)
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
                @menu_mode_control.activate_menu_mode(:rss_reader)
              end

              def open_filter_mode
                query = current_menu.rss_filter_query.to_s
                update_menu(mode: :rss_reader_filter, rss_filter_cursor: query.length)
                @menu_mode_control.activate_menu_mode(:rss_reader_filter)
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
                @menu_mode_control.activate_menu_mode(:rss_reader)
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
            end
          end
        end
      end
    end
  end
end
