# frozen_string_literal: true

require_relative '../../../terminal/text_metrics'
require_relative '../ui/text_utils'

module Shoko
  module Adapters::Output::Ui::Components
    module Dictionary
      # Formats dictionary entries for TUI display with styling.
      # Translates the dictionary aesthetic to terminal using ANSI codes and glyphs.
      class EntryFormatter
        include Adapters::Output::Ui::Constants::UI

        GLYPHS = {
          section: '▸',
          bullet: '•',
          arrow: '→',
          star_filled: '★',
          star_empty: '☆',
          bar_filled: '█',
          bar_empty: '▒'
        }.freeze

        SCORE_BAR_LENGTH = 5
        IMPORTANCE_STARS = 5

        def initialize(width:)
          @width = width
          @content_width = [width - 4, 10].max
        end

        # Format a DictionaryResult for display
        # @param result [Core::Models::DictionaryResult]
        # @return [Array<String>] Formatted lines
        def format_result(result, entry_index: nil)
          return format_unavailable(result) if result.search_mode == :unavailable
          return format_error(result) if result.search_mode == :error
          return format_not_found(result.query) if result.empty?

          lines = []
          lines.concat(format_header(result))
          lines << ''

          entries = select_entries(result, entry_index)
          entries.each_with_index do |entry, idx|
            lines.concat(format_entry(entry))
            lines << '' unless idx == entries.length - 1
          end

          lines.concat(format_footer(result, entry_index: entry_index))
          lines
        end

        # Format a single DictionaryEntry
        # @param entry [Core::Models::DictionaryEntry]
        # @return [Array<String>] Formatted lines
        def format_entry(entry)
          lines = []

          # Word header with bold
          lines << format_word_line(entry.word, entry.language)

          # Lexentry if present
          lines << format_lexentry(entry.lexentry) if entry.lexentry && !entry.lexentry.empty?

          # Senses grouped by part of speech
          lines.concat(format_senses(entry.senses))

          # Translations
          lines.concat(format_translations(entry.translations))

          # Score and importance
          lines << format_scores(entry.score, entry.importance)

          lines
        end

        # Format fuzzy search results
        # @param matches [Array<Core::Models::FuzzyMatch>]
        # @param query [String]
        # @return [Array<String>]
        def format_fuzzy_results(matches, query)
          return format_not_found(query) if matches.empty?

          lines = []
          lines << "#{dim}Similar words for '#{reset}#{bold}#{query}#{reset}#{dim}':#{reset}"
          lines << ''

          matches.each_with_index do |match, idx|
            lines << format_fuzzy_match(match, idx + 1)
          end

          lines << ''
          lines << "#{dim}Select a word for full definition#{reset}"
          lines
        end

        private

        def format_header(result)
          [
            "#{bold}#{GLYPHS[:section]} Look Up#{reset}",
            "#{dim}#{result.source_lang&.upcase} → #{result.target_lang&.upcase}#{reset}"
          ]
        end

        def format_footer(result, entry_index: nil)
          entry_info = if entry_index && result.entry_count > 1
                         "Result #{entry_index + 1}/#{result.entry_count}"
                       else
                         "#{result.entry_count} result(s)"
                       end
          [
            "#{dim}─#{reset}" * [@content_width, 1].max,
            "#{dim}#{entry_info} • Press Esc to close#{reset}"
          ]
        end

        def format_word_line(word, language)
          lang_part = language ? "  #{dim}#{italic}#{language}#{reset}" : ''
          "#{bold}#{accent}#{word}#{reset}#{lang_part}"
        end

        def format_lexentry(lexentry)
          "#{dim}#{lexentry}#{reset}"
        end

        def format_senses(senses)
          return [] if senses.empty?

          lines = []
          senses.each_with_index do |sense, idx|
            lines.concat(format_sense(sense, idx + 1))
          end
          lines
        end

        def format_sense(sense, number)
          lines = []
          wrapped = word_wrap(sense, @content_width - 4)

          wrapped.each_with_index do |line, idx|
            prefix = idx.zero? ? "  #{dim}#{number}.#{reset} " : '     '
            lines << "#{prefix}#{line}"
          end

          lines
        end

        def format_translations(translations)
          return [] if translations.empty?

          lines = ['']
          lines << "  #{accent}Translations:#{reset}"

          translations.each do |trans|
            wrapped = word_wrap(trans, @content_width - 6)
            wrapped.each_with_index do |line, idx|
              prefix = idx.zero? ? "    #{cyan}#{GLYPHS[:arrow]}#{reset} " : '      '
              lines << "#{prefix}#{line}"
            end
          end

          lines
        end

        def format_scores(score, importance)
          score_bar = progress_bar(score, SCORE_BAR_LENGTH)
          importance_bar = star_bar(importance)
          "  #{dim}Score: #{score_bar}  #{importance_bar}#{reset}"
        end

        def format_fuzzy_match(match, number)
          similarity_pct = (match.similarity * 100).round
          bar = similarity_bar(match.similarity)
          word_display = "#{cyan}#{match.word.ljust(20)}#{reset}"
          "#{bold}#{number}.#{reset} #{word_display} #{bar} #{dim}#{similarity_pct}%#{reset}"
        end

        def format_not_found(query)
          [
            "#{yellow}No results found for '#{bold}#{query}#{reset}#{yellow}'#{reset}",
            '',
            "#{dim}Suggestions:#{reset}",
            "#{dim}  #{GLYPHS[:bullet]} Check spelling#{reset}",
            "#{dim}  #{GLYPHS[:bullet]} Try a different word#{reset}",
            '',
            "#{dim}Press Esc to close#{reset}"
          ]
        end

        def format_unavailable(result)
          [
            "#{yellow}Dictionary not available#{reset}",
            '',
            "#{dim}Language pair #{result.source_lang}-#{result.target_lang} not found.#{reset}",
            "#{dim}Check that dictionary databases are installed.#{reset}",
            '',
            "#{dim}Press Esc to close#{reset}"
          ]
        end

        def format_error(result)
          custom = result.respond_to?(:error_message) ? result.error_message : nil
          custom = nil if custom&.strip.to_s.empty?
          [
            "#{red}Dictionary lookup failed#{reset}",
            '',
            "#{dim}#{custom || 'Try again or check dictionary configuration.'}#{reset}",
            '',
            "#{dim}Press Esc to close#{reset}"
          ]
        end

        def select_entries(result, entry_index)
          entries = result.entries
          return entries unless entry_index && !entries.empty?

          index = entry_index % entries.length
          entry = entries[index]
          entry ? [entry] : []
        end

        def progress_bar(value, length)
          bars = (value * length).round.clamp(0, length)
          "#{green}#{GLYPHS[:bar_filled] * bars}#{reset}#{dim}#{GLYPHS[:bar_empty] * (length - bars)}#{reset}"
        end

        def star_bar(value)
          stars = (value * IMPORTANCE_STARS).round.clamp(0, IMPORTANCE_STARS)
          "#{yellow}#{GLYPHS[:star_filled] * stars}#{reset}#{dim}#{GLYPHS[:star_empty] * (IMPORTANCE_STARS - stars)}#{reset}"
        end

        def similarity_bar(value)
          color = case value
                  when 0.8..1.0 then green
                  when 0.6...0.8 then yellow
                  else red
                  end
          bars = (value * SCORE_BAR_LENGTH).round.clamp(0, SCORE_BAR_LENGTH)
          "#{color}#{GLYPHS[:bar_filled] * bars}#{reset}#{dim}#{GLYPHS[:bar_empty] * (SCORE_BAR_LENGTH - bars)}#{reset}"
        end

        def word_wrap(text, width)
          return [text] if text.length <= width

          text.split.each_with_object([]) do |word, lines|
            if lines.empty? || (lines.last.length + word.length + 1) > width
              lines << word
            else
              lines[-1] = "#{lines.last} #{word}"
            end
          end
        end

        # ANSI color helpers
        def reset
          Terminal::ANSI::RESET
        end

        def bold
          "\e[1m"
        end

        def dim
          "\e[2m"
        end

        def italic
          "\e[3m"
        end

        def cyan
          "\e[36m"
        end

        def green
          "\e[32m"
        end

        def yellow
          "\e[33m"
        end

        def red
          "\e[31m"
        end

        def accent
          RenderStyle.color(:accent)
        rescue StandardError
          cyan
        end
      end
    end
  end
end
