# frozen_string_literal: true

module Shoko
  module Core
    module Services
      # Keeps editor cursors on boundaries between user-perceived characters.
      # Offsets remain Ruby character indices so persisted cursor state and
      # existing layout APIs do not need a representation migration.
      module GraphemeCursor
        module_function

        def boundaries(text)
          offset = 0
          [0].tap do |positions|
            text.to_s.each_grapheme_cluster do |cluster|
              offset += cluster.length
              positions << offset
            end
          end
        end

        def clamp(text, cursor)
          requested = cursor.to_i.clamp(0, text.to_s.length)
          boundaries(text).reverse_each.find { |boundary| boundary <= requested } || 0
        end

        def previous(text, cursor)
          current = clamp(text, cursor)
          boundaries(text).reverse_each.find { |boundary| boundary < current } || 0
        end

        def next(text, cursor)
          current = clamp(text, cursor)
          boundaries(text).find { |boundary| boundary > current } || text.to_s.length
        end

        def ceiling(text, cursor)
          requested = cursor.to_i.clamp(0, text.to_s.length)
          boundaries(text).find { |boundary| boundary >= requested } || text.to_s.length
        end

        def end_index(text) = text.to_s.length
        def count(text) = text.to_s.each_grapheme_cluster.count
      end
    end
  end
end
