# frozen_string_literal: true

require 'shoko/core/models/content_block'

module Shoko
  module Adapters
    module Rss
      # An extracted article: its readable text and the structure that text was
      # flattened from.
      #
      # Both travel together because every consumer needs one or the other and
      # they must describe the same content — the length comparisons that decide
      # whether a fetched page beats the feed excerpt read `text`, while the
      # reading pane renders `blocks`.
      ArticleContent = Data.define(:text, :blocks) do
        def initialize(text: '', blocks: [])
          super(text: text.to_s, blocks: Array(blocks).freeze)
        end

        def empty? = text.strip.empty?

        # Longest-wins comparisons treat the content as its text.
        def to_s = text
        def length = text.length
        def strip = text.strip
      end
    end
  end
end
