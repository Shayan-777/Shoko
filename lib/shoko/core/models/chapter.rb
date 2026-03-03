# frozen_string_literal: true

require_relative '../ports/outbound/reader_chapter'

module Shoko
  module Core
  module Models
      # Represents a chapter within an EPUB document.
      Chapter = Struct.new(:number, :title, :lines, :metadata, :blocks, :raw_content,
                           keyword_init: true) do
        include Shoko::Core::Ports::Outbound::ReaderChapter

        # Number of lines in the chapter
        # @return [Integer]
        def line_count
          lines.size
        end

        # Estimated reading time in minutes
        # @param wpm [Integer] words per minute
        # @return [Integer]
        def estimated_reading_time(wpm = 250)
          word_count = lines.join(' ').split.size
          (word_count / wpm.to_f).ceil
        end
      end
    end
  end
end
