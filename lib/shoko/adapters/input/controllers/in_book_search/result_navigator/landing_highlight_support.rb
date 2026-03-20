# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        class InBookSearchController
          class ResultNavigator
            # Builds the transient landing highlight shown after a search result jump.
            module LandingHighlightSupport
              private

              def set_search_landing_highlight(result_entry, chapter_index:, line_offset:)
                payload = build_search_landing_highlight(result_entry,
                                                         chapter_index: chapter_index,
                                                         line_offset: line_offset)
                return if payload.nil?

                @reader_session_mutator&.update_reader(search_landing_highlight: payload)
              end

              def build_search_landing_highlight(result_entry, chapter_index:, line_offset:)
                entry = result_entry.is_a?(Hash) ? result_entry : {}
                match_text = result_value(entry, :match)
                return nil if match_text.empty?

                query = result_value(entry, :query)
                query = match_text if query.empty?

                {
                  chapter_index: chapter_index,
                  line_index: line_offset,
                  page_index: current_page_index,
                  expires_at: monotonic_now + LANDING_HIGHLIGHT_DURATION,
                  query: query,
                  before: result_value(entry, :before),
                  match_text: match_text,
                  after: result_value(entry, :after),
                }
              end

              def current_page_index
                @reader_state&.current_page_index
              end

              def chapter_label(result_entry, chapter_index)
                label = result_value(result_entry, :chapter_title).strip
                label.empty? ? "Chapter #{chapter_index + 1}" : label
              end

              def monotonic_now
                @clock&.monotonic_now || Process.clock_gettime(Process::CLOCK_MONOTONIC)
              rescue Shoko::Error, SystemCallError
                Process.clock_gettime(Process::CLOCK_MONOTONIC)
              end
            end
          end
        end
      end
    end
  end
end
