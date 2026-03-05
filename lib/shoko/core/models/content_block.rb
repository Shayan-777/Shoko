# frozen_string_literal: true

module Shoko
  module Core
    module Models
      # Represents a unit of formatted content (heading, paragraph, list item, etc.).
      ContentBlock = Struct.new(:type, :segments, :level, :metadata) do
        def text
          segments.to_a.map { |segment| segment&.text.to_s }.join
        end

        def heading_level
          (metadata && metadata[:level]) || level
        end
      end

      # Represents a contiguous run of text with associated inline styles.
      TextSegment = Struct.new(:text, :styles) do
        def initialize(text:, styles: nil)
          super(text: text.to_s, styles: (styles || {}).freeze)
        end

        def length
          text.to_s.length
        end
      end

      # Represents a display-ready line produced by the formatting pipeline.
      DisplayLine = Struct.new(:text, :segments, :metadata) do
        def initialize(text:, segments:, metadata: nil)
          super(text: text.to_s, segments: segments || [], metadata: metadata || {})
        end

        def length
          text.length
        end

        def empty?
          text.strip.empty?
        end
      end
    end
  end
end
