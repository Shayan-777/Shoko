# frozen_string_literal: true

require_relative '../ports/outbound/text_metrics'

module Shoko
  module Core
    module Services
      # Minimal text wrapping implementation used when no adapter is registered.
      class DefaultTextMetrics
        include Core::Ports::Outbound::TextMetrics

        def wrap_plain_text(line, width)
          text = line.to_s
          return [''] if text.strip.empty?

          width_i = width.to_i
          return [text] if width_i <= 0

          words = text.split(/\s+/)
          return [''] if words.empty?

          wrap_words(words, width_i)
        end

        private

        def wrap_words(words, width_i)
          wrapped = []
          current = +''

          words.each do |word|
            current = append_word(current, word, width_i, wrapped)
          end

          wrapped << current unless current.empty?
          wrapped
        end

        def append_word(current, word, width_i, wrapped)
          return current if word.empty?
          return current << word if current.empty?
          return current << ' ' << word if (current.length + 1 + word.length) <= width_i

          wrapped << current
          word.dup
        end
      end
    end
  end
end
