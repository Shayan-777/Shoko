# frozen_string_literal: true

require_relative '../../constants/ui_constants'
require 'shoko/shared/terminal/text_metrics'
require_relative '../ui/text_utils'

module Shoko
  module Adapters
    module Ui
      module Components
        module Dictionary
          # Formats dictionary entries for TUI display.
          # Uses bold, italic, and subtle styling for clean visual hierarchy.
          class EntryFormatter
            include Adapters::Ui::Constants::Ui

            # ANSI style codes (not colors, just styles)
            BOLD = "\e[1m"
            DIM = "\e[2m"
            ITALIC = "\e[3m"
            RESET_STYLE = "\e[22;23;24m" # Reset bold, italic, underline only (not colors/bg)

            LANG_NAMES = {
              'en' => 'English',
              'de' => 'German',
              'ru' => 'Russian',
              'zh' => 'Chinese',
              'fr' => 'French',
              'es' => 'Spanish',
              'it' => 'Italian',
              'pt' => 'Portuguese',
              'ja' => 'Japanese',
              'ko' => 'Korean',
            }.freeze

            def initialize(width:, background: nil, accent: nil)
              @width = width
              @content_width = [width - 2, 10].max
              @bg = background || ''
              @accent_override = accent
            end

            def format_result(result, entry_index: nil)
              @target_lang = result.target_lang
              return format_unavailable(result) if result.search_mode == :unavailable
              return format_error(result) if result.search_mode == :error
              return format_not_found(result.query) if result.empty?

              build_result_lines(result, entry_index)
            end

            def format_entry(entry)
              lines = []

              # Main word - bold and accented
              lines << "#{BOLD}#{accent}#{entry.word}#{RESET_STYLE}"

              # Part of speech / grammatical info - italic, only if clean
              if entry.lexentry && !entry.lexentry.empty? && clean_lexentry?(entry.lexentry)
                lines << "#{DIM}#{ITALIC}#{format_lexentry(entry.lexentry)}#{RESET_STYLE}"
              end

              lines << ''

              # Definitions/senses
              lines.concat(format_senses(entry.senses))

              # Translations with label
              lines.concat(format_translations(entry.translations))

              lines
            end

            # The body of an entry without its headword line: part-of-speech (when
            # clean), definitions/senses, and translations. Used by the reader's
            # left "Definition card", which carries the headword on its top rule.
            def format_entry_body(entry)
              lines = []
              pos = entry_pos_line(entry)
              if pos
                lines << pos
                lines << ''
              end
              lines.concat(format_senses(entry.senses))
              lines.concat(format_translations(entry.translations))
              lines
            end

            def format_fuzzy_results(matches, query)
              return format_not_found(query) if matches.empty?

              lines = []
              lines << "#{DIM}Similar to#{RESET_STYLE} #{BOLD}#{query}#{RESET_STYLE}"
              lines << ''

              matches.first(8).each_with_index do |match, idx|
                pct = (match.similarity * 100).round
                lines << fuzzy_match_line(match, idx, pct)
              end

              lines
            end

            private

            def format_header(result)
              src = result.source_lang&.upcase || '?'
              tgt = result.target_lang&.upcase || '?'
              ["#{DIM}#{src} → #{tgt}#{RESET_STYLE}", '']
            end

            def format_footer(result, entry_index: nil)
              return [] unless entry_index && result.entry_count > 1

              ['', "#{DIM}#{entry_index + 1} of #{result.entry_count}#{RESET_STYLE}"]
            end

            def build_result_lines(result, entry_index)
              lines = format_header(result)
              append_entries(lines, select_entries(result, entry_index))
              lines.concat(format_footer(result, entry_index: entry_index))
              lines
            end

            def append_entries(lines, entries)
              entries.each_with_index do |entry, idx|
                lines.concat(format_entry(entry))
                lines << '' unless idx == entries.length - 1
              end
            end

            def format_lexentry(lexentry)
              # Clean up ugly database IDs like "eng/revolutionary__Noun__1"
              cleaned = lexentry.to_s
                                .gsub(%r{^[a-z]{2,3}/}, '')  # Remove language prefix
                                .gsub(/__\d+$/, '')          # Remove trailing numbers
                                .gsub('__', ' · ')           # Replace __ with dot
                                .tr('_', ' ')
              cleaned.split(' · ').map(&:capitalize).join(' · ')
            end

            def clean_lexentry?(lexentry)
              return false if lexentry.to_s.strip.empty?
              return false if lexentry.to_s.length > 50

              true
            end

            def format_senses(senses)
              return [] if senses.empty?

              lines = []
              senses.first(4).each_with_index do |sense, idx|
                wrapped = Ui::TextUtils.wrap_words(sense, @content_width - 4)
                wrapped.each_with_index do |line, line_idx|
                  lines << if line_idx.zero?
                             "#{DIM}#{idx + 1}.#{RESET_STYLE} #{line}"
                           else
                             "   #{line}"
                           end
                end
              end
              lines
            end

            def format_translations(translations)
              return [] if translations.empty?

              [''].concat(translation_header).concat(formatted_translation_lines(translations))
            end

            def format_not_found(query)
              [
                "No results for #{BOLD}#{query}#{RESET_STYLE}",
                '',
                "#{DIM}Try different spelling or press f for fuzzy search#{RESET_STYLE}",
              ]
            end

            def format_unavailable(result)
              [
                'Dictionary unavailable',
                '',
                "#{DIM}#{result.source_lang}-#{result.target_lang} not installed#{RESET_STYLE}",
              ]
            end

            def format_error(result)
              msg = result.error_message
              msg = nil if msg.to_s.strip.empty?
              [
                'Lookup failed',
                '',
                "#{DIM}#{msg || 'Please try again'}#{RESET_STYLE}",
              ]
            end

            def select_entries(result, entry_index)
              entries = result.entries
              return entries unless entry_index && !entries.empty?

              index = entry_index % entries.length
              entry = entries[index]
              entry ? [entry] : []
            end

            def fuzzy_match_line(match, idx, pct)
              [
                "  #{DIM}#{idx + 1}.#{RESET_STYLE}",
                "#{accent}#{match.word}#{RESET_STYLE}",
                "#{DIM}#{pct}%#{RESET_STYLE}",
              ].join(' ')
            end

            def translation_header
              lang_name = LANG_NAMES[@target_lang&.downcase] || @target_lang&.capitalize || 'Translation'
              ["#{DIM}#{lang_name}:#{RESET_STYLE}"]
            end

            def formatted_translation_lines(translations)
              translations.first(4).flat_map do |translation|
                Ui::TextUtils.wrap_words(translation, @content_width - 4).each_with_index.map do |line, idx|
                  idx.zero? ? "  #{accent}→#{RESET_STYLE} #{line}" : "    #{line}"
                end
              end
            end

            def entry_pos_line(entry)
              return nil unless entry.lexentry && !entry.lexentry.empty? && clean_lexentry?(entry.lexentry)

              "#{DIM}#{ITALIC}#{format_lexentry(entry.lexentry)}#{RESET_STYLE}"
            end

            def accent
              return @accent_override if @accent_override

              RenderStyle.color(:accent)
            end
          end
        end
      end
    end
  end
end
