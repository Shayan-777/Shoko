# frozen_string_literal: true

module Shoko
  module Adapters
    module BookSources
      module Epub
        class XHTMLBlockBuilder
          # Shared anchor/alignment extraction for block metadata assembly.
          module BlockMetadataSupport
            private

            def attach_anchor_metadata(metadata, element)
              anchors = anchor_ids_for(element)
              metadata[:anchors] = anchors if anchors
            end

            def anchor_ids_for(element)
              return nil unless element.is_a?(REXML::Element)

              ids = []
              collect_anchor_ids(element, ids)
              ids = ids.map { |value| value.to_s.strip }.reject(&:empty?).uniq
              ids.empty? ? nil : ids
            end

            def collect_anchor_ids(element, ids)
              return unless element.is_a?(REXML::Element)

              anchor = element.attributes['id'] || element.attributes['name']
              ids << anchor if anchor && !anchor.to_s.empty?
              element.each_element { |child| collect_anchor_ids(child, ids) }
            end

            def alignment_for(element)
              return nil unless element.is_a?(REXML::Element)

              style_align = alignment_from_style(element.attributes['style'])
              attr_align = element.attributes['align']
              normalize_alignment(style_align || attr_align)
            end

            def alignment_from_style(style)
              style_text = style.to_s
              return nil if style_text.empty?

              match = /text-align\s*:\s*([^;]+)/i.match(style_text)
              match ? match[1] : nil
            end

            def normalize_alignment(value)
              raw = value.to_s.strip.downcase
              return nil if raw.empty?

              normalized = raw.sub(/;+\z/, '')
              normalized = normalized.sub(/\s*!important\z/, '').strip
              ALIGNMENT_MAP[normalized]
            end
          end
        end
      end
    end
  end
end
