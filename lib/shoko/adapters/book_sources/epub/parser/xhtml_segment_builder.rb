# frozen_string_literal: true

require 'rexml/document'

require 'shoko/core/models/text_segment'
require 'shoko/shared/text_sanitizer'
require 'shoko/adapters/support/html_processor'
require_relative 'markup_visibility'

module Shoko
  module Adapters
    module BookSources
      module Epub
        # Collects and normalizes inline text segments.
        class XHTMLSegmentBuilder
          TextSegment = Shoko::Core::Models::TextSegment

          STYLE_MAP = {
            'strong' => { bold: true },
            'b' => { bold: true },
            'em' => { italic: true },
            'i' => { italic: true },
            'u' => { underline: true },
            's' => { strikethrough: true },
            'strike' => { strikethrough: true },
            'del' => { strikethrough: true },
            'sup' => { superscript: true },
            'sub' => { subscript: true },
            'code' => { code: true, preserve_whitespace: true },
            'kbd' => { code: true, preserve_whitespace: true },
            'samp' => { code: true, preserve_whitespace: true },
            'cite' => { italic: true },
            'dfn' => { italic: true },
            'var' => { italic: true },
            'mark' => { highlight: true },
            'ins' => { underline: true },
            'tt' => { code: true },
            'small' => { small: true },
            'big' => { large: true },
          }.freeze

          SPAN_STYLE_MATCHERS = {
            bold: /font-weight\s*:\s*(?:bold|[6-9]00)/i,
            italic: /font-style\s*:\s*(?:italic|oblique)/i,
            underline: /text-decoration(?:-line)?\s*:\s*[^;]*underline/i,
            strikethrough: /text-decoration(?:-line)?\s*:\s*[^;]*(?:line-through|line\s+through)/i,
            superscript: /vertical-align\s*:\s*super/i,
            subscript: /vertical-align\s*:\s*sub/i,
            small_caps: /font-variant(?:-caps)?\s*:\s*[^;]*small-caps/i,
          }.freeze

          COLOR_STYLE_PATTERN = /(?<!background-)\bcolor\s*:\s*([^;]+)/i
          BACKGROUND_STYLE_PATTERN = /background(?:-color)?\s*:\s*([^;]+)/i
          NON_COLOR_VALUES = %w[inherit initial unset transparent currentcolor none].freeze
          SKIPPED_INLINE_ELEMENTS = %w[rt rp].freeze
          MAX_ALT_LENGTH = 60

          PLACEHOLDER_TEXT = '[Image]'

          def initialize(tag_sets:, whitespace_pattern:, style_resolver: nil)
            @br_tag = tag_sets[:br]
            @img_tag = tag_sets[:img]
            @inline_newline = tag_sets[:inline_newline]
            @whitespace_pattern = whitespace_pattern
            @style_resolver = style_resolver
          end

          def collect_segments(element, inherited_styles = {})
            element.children.flat_map { |child| segments_for(child, inherited_styles) }
          end

          def segments_from_children(children, inherited_styles = {})
            Array(children).flat_map { |child| segments_for(child, inherited_styles) }
          end

          def text_segment(text, styles = {})
            TextSegment.new(text: normalize_text(text.to_s, styles), styles: styles)
          end

          def image_placeholder_segment(inherited_styles, alt: nil)
            placeholder_segment(inherited_styles.merge(dim: true), alt)
          end

          def inline_image_placeholder_segment(element, inherited_styles)
            attrs = element.attributes
            alt = attrs['alt'].to_s.strip
            styles = inherited_styles.merge(
              dim: true,
              inline_image: { src: attrs['src'].to_s, alt: alt }
            )
            placeholder_segment(styles, alt)
          end

          # Inline styles derived from an element's style="" attribute. Public so
          # block builders can seed inherited styles for block-level elements.
          def style_attributes(element)
            style_attr = element.attributes['style'].to_s
            return {} if style_attr.empty?

            styles = SPAN_STYLE_MATCHERS.each_with_object({}) do |(key, matcher), acc|
              acc[key] = true if matcher.match?(style_attr)
            end
            apply_color_styles(styles, style_attr)
            styles
          end

          def finalize_segments(segments)
            segs = compact_segments(segments)
            return [] if segs.empty?

            segs = collapse_boundary_spaces(segs)
            trim_edge_whitespace(segs)
          end

          private

          def segments_for(child, inherited_styles)
            return [] unless child

            if child.is_a?(REXML::Text)
              segment = text_segment(child.value, inherited_styles)
              segment.text.to_s.empty? ? [] : [segment]
            elsif child.is_a?(REXML::Element)
              segments_for_element(child, inherited_styles)
            else
              []
            end
          end

          def segments_for_element(element, inherited_styles)
            name = element.name.downcase
            return [] if SKIPPED_INLINE_ELEMENTS.include?(name)
            return [] if MarkupVisibility.markup_hidden?(element)
            return [] if @style_resolver&.display_none?(element)
            return [line_break_segment(inherited_styles)] if name == @br_tag
            return [inline_image_placeholder_segment(element, inherited_styles)] if name == @img_tag

            new_styles = inherited_styles.merge(styles_for(name, element))
            collect_segments(element, new_styles)
          end

          def line_break_segment(inherited_styles)
            text_segment(@inline_newline, inherited_styles.merge(break: true))
          end

          def styles_for(name, element)
            base = STYLE_MAP[name] || {}
            css = @style_resolver ? @style_resolver.inline_styles(element) : {}
            base = base.merge(css) unless css.empty?
            base = base.merge(link_styles(element)) if name == 'a'
            base = base.merge(font_attribute_styles(element)) if name == 'font'
            attr_styles = style_attributes(element)
            attr_styles.empty? ? base : base.merge(attr_styles)
          end

          # Footnote references render as superscript marks even without CSS.
          def link_styles(element)
            styles = { link: element.attributes['href'] }
            styles[:superscript] = true if element.attributes['epub:type'].to_s.include?('noteref')
            styles
          end

          def font_attribute_styles(element)
            color = element.attributes['color'].to_s.strip
            color.empty? ? {} : { fg: color }
          end

          def apply_color_styles(styles, style_attr)
            fg = color_style_value(style_attr, COLOR_STYLE_PATTERN)
            bg = color_style_value(style_attr, BACKGROUND_STYLE_PATTERN)
            styles[:fg] = fg if fg
            styles[:bg] = bg if bg
          end

          def color_style_value(style_attr, pattern)
            match = pattern.match(style_attr)
            return nil unless match

            value = match[1].to_s.sub(/\s*!important\z/i, '').strip
            return nil if value.empty? || NON_COLOR_VALUES.include?(value.downcase)

            value
          end

          def normalize_text(text, styles)
            decoded = apply_transform(decode_text(text), styles)
            return decoded if preserve_whitespace?(styles)
            return normalize_break(decoded) if styles[:break]

            normalize_whitespace(decoded)
          end

          def apply_transform(text, styles)
            styles[:transform] == :upcase ? text.upcase : text
          end

          def decode_text(text)
            decoded = Shoko::Adapters::Support::HTMLProcessor.decode_entities(text)
            Shoko::Shared::TextSanitizer.sanitize(decoded, preserve_newlines: true, preserve_tabs: true)
          end

          def preserve_whitespace?(styles)
            styles[:code] || styles[:preserve_whitespace]
          end

          def normalize_break(text)
            text == @inline_newline ? @inline_newline : text
          end

          def normalize_whitespace(text)
            text.delete("\r").tr("\n", ' ').gsub(@whitespace_pattern, ' ')
          end

          def placeholder_segment(styles, alt = nil)
            text_segment(" #{placeholder_text(alt)} ", styles)
          end

          def placeholder_text(alt)
            cleaned = alt.to_s.gsub(/\s+/, ' ').strip
            return PLACEHOLDER_TEXT if cleaned.empty?

            cleaned = "#{cleaned[0, MAX_ALT_LENGTH - 1]}…" if cleaned.length > MAX_ALT_LENGTH
            "[Image: #{cleaned}]"
          end

          def compact_segments(segments)
            Array(segments).compact.reject { |segment| segment_text(segment).empty? }
          end

          def collapse_boundary_spaces(segments)
            out = [segments.first]
            segments.drop(1).each do |segment|
              previous = out.last
              adjusted = adjust_leading_space(previous, segment)
              next unless adjusted

              out << adjusted unless segment_text(adjusted).empty?
            end
            out
          end

          def adjust_leading_space(previous, segment)
            prev_text = segment_text(previous)
            cur_text = segment_text(segment)
            return segment unless prev_text.end_with?(' ') && cur_text.start_with?(' ')

            trimmed = cur_text.sub(/\A +/, '')
            return nil if trimmed.empty?

            TextSegment.new(text: trimmed, styles: segment.styles)
          end

          def trim_edge_whitespace(segments)
            segs = segments.dup
            return [] if segs.empty?

            segs[0] = trim_segment_start(segs[0])
            segs[-1] = trim_segment_end(segs[-1])
            segs.reject { |segment| segment_text(segment).empty? }
          end

          def trim_segment_start(segment)
            text = segment_text(segment).sub(/\A\s+/, '')
            TextSegment.new(text: text, styles: segment.styles)
          end

          def trim_segment_end(segment)
            text = segment_text(segment).sub(/\s+\z/, '')
            TextSegment.new(text: text, styles: segment.styles)
          end

          def segment_text(segment)
            segment.text.to_s
          end
        end
      end
    end
  end
end
