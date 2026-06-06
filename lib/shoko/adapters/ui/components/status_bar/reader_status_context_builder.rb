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
          # results render as an upward list above the bar. Dictionary lookup is
          # the same idea: a "Define/<format>" input with a definition status,
          # while the teal definition card floats above the bar.
          class ReaderStatusContextBuilder
            HIDDEN_MODES = %i[help].freeze
            SEARCH_PLACEHOLDER = 'type to search…'
            DICTIONARY_PLACEHOLDER = 'type a word to define…'
            TOC_PLACEHOLDER = 'type to filter chapters…'

            def initialize(view_model_provider, reader_state_reader: nil)
              @view_model_provider = view_model_provider
              @reader_state_reader = reader_state_reader
            end

            def call
              view_model = @view_model_provider&.call
              return nil unless view_model
              return nil if HIDDEN_MODES.include?(view_model.mode)
              return search_context(view_model) if view_model.mode == :in_book_search
              return dictionary_context(view_model) if view_model.mode == :dictionary
              return toc_context(view_model) if view_model.mode == :toc

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
              query = state_value(:search_query).to_s

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

              results = Array(state_value(:search_results))
              results_query = state_value(:search_results_query).to_s

              return '↵ to search' if query.strip != results_query.strip
              return 'no matches' if results.empty?

              selected = state_value(:search_selected_index).to_i.clamp(0, results.length - 1)
              "#{selected + 1} / #{results.length}"
            end

            # ----- dictionary -----

            def dictionary_context(view_model)
              query = state_value(:dictionary_query).to_s

              StatusContext.build(
                badge: FormatBadge.mode_badge('Dictionary', view_model.source_format),
                title: query,
                placeholder: DICTIONARY_PLACEHOLDER,
                caret: true,
                trailing: [dictionary_status(query)]
              )
            end

            def dictionary_status(query)
              return '' if query.strip.empty?

              results_query = state_value(:dictionary_results_query).to_s
              return '↵ to define' if query.strip != results_query.strip
              return fuzzy_status if state_value(:dictionary_fuzzy_mode) == true

              result = state_value(:dictionary_result)
              entry_status(result)
            end

            def fuzzy_status
              count = Array(state_value(:dictionary_fuzzy_matches)).length
              count.zero? ? 'no similar' : "#{count} similar"
            end

            # ----- table of contents -----

            def toc_context(view_model)
              query = state_value(:toc_query).to_s

              StatusContext.build(
                badge: FormatBadge.mode_badge('TOC', view_model.source_format),
                title: query,
                placeholder: TOC_PLACEHOLDER,
                caret: true,
                trailing: [toc_status(query)]
              )
            end

            def toc_status(query)
              rows = Array(state_value(:toc_visible_entries))
              chapters = rows.count { |row| toc_navigable?(row) }
              return "#{chapters} #{chapters == 1 ? 'chapter' : 'chapters'}" if query.strip.empty?
              return 'no matches' if chapters.zero?

              "#{toc_selected_rank(rows)} / #{chapters}"
            end

            # Rank of the selected row among navigable rows (1-based), mirroring the
            # search "k / n" counter.
            def toc_selected_rank(rows)
              selected = state_value(:toc_selected_index).to_i.clamp(0, [rows.length - 1, 0].max)
              rows[0..selected].count { |row| toc_navigable?(row) }
            end

            def toc_navigable?(row)
              return false unless row.is_a?(Hash)

              (row.key?(:navigable) ? row[:navigable] : row['navigable']) != false
            end

            def entry_status(result)
              return 'no entry' if result.nil?
              return 'not installed' if result.search_mode == :unavailable
              return 'error' if result.search_mode == :error
              return 'no entry' if result.respond_to?(:empty?) && result.empty?

              entry_count_status(result)
            end

            def entry_count_status(result)
              count = result.entry_count
              return "#{(state_value(:dictionary_entry_index).to_i % count) + 1} / #{count}" if count > 1

              senses = Array(result.primary_entry&.senses).length
              return "#{senses} sense#{'s' unless senses == 1}" if senses.positive?

              'defined'
            end

            def state_value(field)
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
