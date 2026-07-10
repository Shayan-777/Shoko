# frozen_string_literal: true

require_relative 'status_context'
require_relative 'format_badge'
require_relative '../ui/spinner'
require 'shoko/shared/language_directory'

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
            TRANSLATOR_HINT = '↵ translate · Tab languages · ⇧Tab swap · Esc'
            TRANSLATOR_PICKER_HINT = 'type to filter · ←/→ switch · ↵ pick · Esc'
            NOTES_BADGE = 'Annotation Notes'
            NOTES_LIST_HINT = '↑/↓ browse · ↵ go · e edit · n new · d delete · Esc'
            NOTES_COMPOSE_HINT = '↵ save · ⇧↵ newline · Esc back'

            # Suppress the recalculation spinner until a rebuild has run this long,
            # so fast repaginations don't flash a throbber for a few milliseconds.
            RECALC_GRACE_SECONDS = 0.15
            Spinner = Shoko::Adapters::Ui::Components::Ui::Spinner

            def initialize(view_model_provider, reader_state_reader: nil, recalc_status_reader: nil)
              @view_model_provider = view_model_provider
              @reader_state_reader = reader_state_reader
              @recalc_status_reader = recalc_status_reader
            end

            def call
              view_model = @view_model_provider&.call
              return nil unless view_model
              return nil if HIDDEN_MODES.include?(view_model.mode)
              return search_context(view_model) if view_model.mode == :in_book_search
              return dictionary_context(view_model) if view_model.mode == :dictionary
              return toc_context(view_model) if view_model.mode == :toc
              return translator_context(view_model) if view_model.mode == :translator
              return notes_context(view_model) if view_model.mode == :notes

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
                trailing: [reading_trailing(pages)],
                progress: progress_fraction(pages),
                progress_rgb: badge&.rgb
              )
            end

            # While a background repagination is in flight (past a short grace
            # period) the trailing slot shows an animated spinner instead of the
            # page counter — which is mid-rebuild and would read as a stale
            # "Page N" until the new total lands.
            def reading_trailing(pages)
              recalculation_label || pages_label(pages)
            end

            def recalculation_label
              status = recalc_status
              unless status&.active
                @recalc_first_seen_at = nil
                return nil
              end

              now = monotonic_now
              @recalc_first_seen_at ||= now
              return nil if (now - @recalc_first_seen_at) < RECALC_GRACE_SECONDS

              message = status.message.to_s.strip
              message = 'Repaginating…' if message.empty?
              "#{Spinner.glyph} #{message}#{recalc_percent(status)}"
            end

            def recalc_percent(status)
              progress = status.progress.to_f
              return '' unless progress.positive?

              " #{(progress * 100).round}%"
            end

            def recalc_status
              @recalc_status_reader&.recalc_status
            end

            def monotonic_now
              Process.clock_gettime(Process::CLOCK_MONOTONIC)
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

            # ----- translator -----

            # The translator keeps its source text inside the card (a multi-line
            # editor), so the bar is a quiet toolbar: the language pair as the title,
            # the live translate status and key hints trailing. With the picker open it
            # names the side being chosen and the match count (the filter itself shows
            # in the card's picker header).
            def translator_context(view_model)
              return translator_picker_context(view_model) if translator_picker_open?

              StatusContext.build(
                badge: FormatBadge.mode_badge('Translator', view_model.source_format),
                title: translator_pair_label,
                trailing: [translator_status, TRANSLATOR_HINT]
              )
            end

            def translator_picker_context(view_model)
              count = translator_picker_count
              StatusContext.build(
                badge: FormatBadge.mode_badge('Translator', view_model.source_format),
                title: "Languages · #{translator_picker_side_label}",
                trailing: ["#{count} #{count == 1 ? 'match' : 'matches'}", TRANSLATOR_PICKER_HINT]
              )
            end

            def translator_picker_open?
              !state_value(:translator_picker_side).nil?
            end

            def translator_pair_label
              src = translator_lang_code(state_value(:translator_source_lang))
              tgt = translator_lang_code(state_value(:translator_target_lang))
              "#{src} → #{tgt}"
            end

            def translator_lang_code(code)
              text = code.to_s.strip
              return '?' if text.empty?

              text.casecmp?(Shoko::Shared::LanguageDirectory::AUTO) ? 'auto' : text.downcase
            end

            def translator_status
              query = state_value(:translator_query).to_s
              return '' if query.strip.empty?

              results_query = state_value(:translator_results_query).to_s
              return '↵ translate' if query.strip != results_query.strip

              result = state_value(:translator_result)
              return '' if result.nil?
              return 'failed' if result.error?

              'translated'
            end

            def translator_picker_side_label
              state_value(:translator_picker_side).to_s == 'source' ? 'Source' : 'Target'
            end

            def translator_picker_count
              Shoko::Shared::LanguageDirectory.candidates_for(
                state_value(:translator_languages),
                side: state_value(:translator_picker_side),
                query: state_value(:translator_picker_query).to_s
              ).length
            end

            # ----- annotation notes -----

            # The notes panel keeps its content inside the card (the list, or the
            # compose editor), so the bar is a quiet toolbar: the badge flips to
            # "Annotation Notes", the title names the note count (or the compose
            # action), and the hints trail.
            def notes_context(view_model)
              return notes_compose_context(view_model) if notes_composing?

              count = Array(state_value(:annotations)).length
              StatusContext.build(
                badge: FormatBadge.mode_badge(NOTES_BADGE, view_model.source_format),
                title: "#{count} #{count == 1 ? 'note' : 'notes'}",
                trailing: [NOTES_LIST_HINT]
              )
            end

            def notes_compose_context(view_model)
              editing = !state_value(:notes_editing_id).nil?
              StatusContext.build(
                badge: FormatBadge.mode_badge(NOTES_BADGE, view_model.source_format),
                title: editing ? 'Edit note' : 'New note',
                trailing: [NOTES_COMPOSE_HINT]
              )
            end

            def notes_composing?
              state_value(:notes_composing) == true
            end

            def entry_status(result)
              return 'no entry' if result.nil?
              return 'not installed' if result.search_mode == :unavailable
              return 'error' if result.search_mode == :error
              return 'no entry' if result.empty?

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
