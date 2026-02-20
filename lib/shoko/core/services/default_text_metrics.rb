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

          wrapped = []
          current = +''

          words.each do |word|
            next if word.empty?

            if current.empty?
              current << word
            elsif (current.length + 1 + word.length) <= width_i
              current << ' ' << word
            else
              wrapped << current
              current = word.dup
            end
          end

          wrapped << current unless current.empty?
          wrapped
        end
      end
    end
  end
end
