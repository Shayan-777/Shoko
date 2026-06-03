# frozen_string_literal: true

require_relative 'status_context'
require_relative 'format_badge'

module Shoko
  module Adapters
    module Ui
      module Components
        module StatusBar
          # Builds the status-bar context for the reader (in-book) view.
          #
          # While reading it shows a "Reader/<format>" badge, the book title,
          # chapter position/title, page counters, and reading progress. When
          # in-book search is active it becomes the search input itself —
          # "Search/<format>" plus the live query and a match counter — while the
          # results render as an upward list above the bar.
          class ReaderStatusContextBuilder
            HIDDEN_MODES = %i[help].freeze
            SEARCH_PLACEHOLDER = 'type to search…'

            def initialize(view_model_provider, reader_state_reader: nil)
              @view_model_provider = view_model_provider
              @reader_state_reader = reader_state_reader
            end

            def call
              view_model = @view_model_provider&.call
              return nil unless view_model
              return nil if HIDDEN_MODES.include?(view_model.mode)
              return search_context(view_model) if view_model.mode == :in_book_search

              reading_context(view_model)
            end

            private

            def reading_context(view_model)
              badge = FormatBadge.mode_badge('Reader', view_model.source_format)
              pages = page_numbers(view_model)

              StatusContext.build(
                badge: badge,
                title: view_model.document_title,
                details: chapter_details(view_model),
                trailing: [pages_label(pages)],
                progress: progress_fraction(pages),
                progress_rgb: badge&.rgb
              )
            end

            def search_context(view_model)
              query = search_value(:search_query).to_s

              StatusContext.build(
                badge: FormatBadge.mode_badge('Search', view_model.source_format),
                title: query,
                placeholder: SEARCH_PLACEHOLDER,
                caret: true,
                trailing: [search_status(query)]
              )
            end

            # ----- search helpers -----

            def search_status(query)
              return '' if query.strip.empty?

              results = Array(search_value(:search_results))
              results_query = search_value(:search_results_query).to_s

              return '↵ to search' if query.strip != results_query.strip
              return 'no matches' if results.empty?

              selected = search_value(:search_selected_index).to_i.clamp(0, results.length - 1)
              "#{selected + 1} / #{results.length}"
            end

            def search_value(field)
              return nil unless @reader_state_reader.respond_to?(field)

              @reader_state_reader.public_send(field)
            end

            # ----- reading helpers -----

            def chapter_details(view_model)
              total = view_model.total_chapters.to_i
              return [] if total <= 1

              current = view_model.current_chapter.to_i + 1
              ["Ch #{current}/#{total}", view_model.chapter_title.to_s.strip]
            end

            # Normalize single/split page info into { current:, total: }.
            def page_numbers(view_model)
              info = view_model.page_info || {}
              side = info[:left] || info

              { current: side[:current].to_i, total: side[:total].to_i }
            end

            def pages_label(pages)
              current = pages[:current]
              total = pages[:total]
              return '' if current <= 0 && total <= 0
              return "Page #{current}" if total <= 0

              "#{current} / #{total}"
            end

            def progress_fraction(pages)
              total = pages[:total]
              return nil if total <= 0

              pages[:current].to_f / total
            end
          end
        end
      end
    end
  end
end
