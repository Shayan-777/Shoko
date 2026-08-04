# frozen_string_literal: true

require 'shoko/core/models/content_block'
require 'shoko/core/models/text_segment'
require 'shoko/adapters/support/html_processor'

module Shoko
  module Adapters
    module Rss
      # Parses article HTML into the same ContentBlock/TextSegment vocabulary
      # the book pipeline uses, so the reading pane can render an article with
      # its structure intact instead of one flat wall of text.
      #
      # Deliberately not REXML: syndicated article HTML is arbitrary web markup
      # — unclosed <p>, bare <br>, stray attributes — and a strict XML parser
      # rejects it outright. This is a forgiving tag scanner: it only cares
      # about the tags that carry meaning for reading, and unknown tags are
      # transparent rather than fatal.
      class ArticleBlockParser
        ContentBlock = Shoko::Core::Models::ContentBlock
        TextSegment = Shoko::Core::Models::TextSegment

        # Inline tags that add a style to the text they wrap.
        INLINE_STYLES = {
          'strong' => { bold: true },
          'b' => { bold: true },
          'em' => { italic: true },
          'i' => { italic: true },
          'cite' => { italic: true },
          'dfn' => { italic: true },
          'var' => { italic: true },
          'code' => { code: true },
          'kbd' => { code: true },
          'samp' => { code: true },
          'tt' => { code: true },
          'small' => { dim: true },
          'a' => { link: true },
        }.freeze

        # Tags that end the current block and start a new one of the given type.
        BLOCK_TYPES = {
          'p' => :paragraph,
          'div' => :paragraph,
          'section' => :paragraph,
          'article' => :paragraph,
          'blockquote' => :quote,
          'figcaption' => :caption,
          'caption' => :caption,
          'dt' => :paragraph,
          'dd' => :paragraph,
          'td' => :paragraph,
          'th' => :paragraph,
          'tr' => :paragraph,
        }.freeze

        LIST_TAGS = %w[ul ol].freeze
        HEADING = /\Ah([1-6])\z/
        # Structural containers whose text is never article prose.
        DROPPED_TAGS = %w[script style noscript template svg iframe head].freeze
        MAX_LIST_DEPTH = 4
        BULLETS = ['•', '◦', '‣', '·'].freeze

        # @param html [String] article markup
        # @return [Array<Shoko::Core::Models::ContentBlock>]
        def parse(html)
          reset
          scan(html.to_s)
          flush_block
          compact(@blocks)
        end

        private

        def reset
          @blocks = []
          @segments = []
          @styles = []
          @lists = []
          @type = :paragraph
          @heading_level = nil
          @quote_depth = 0
          @preformatted = 0
          @dropped_tags = []
        end

        def scan(html)
          html.scan(/<[^>]*>|[^<]+/m) do |token|
            if token.start_with?('<')
              handle_tag(token)
            else
              handle_text(token)
            end
          end
        end

        # ----- tags -----

        def handle_tag(token)
          closing = token.start_with?('</')
          name = token[%r{\A</?\s*([a-zA-Z][a-zA-Z0-9]*)}, 1]&.downcase
          return unless name

          return handle_dropped(name, closing, token) if DROPPED_TAGS.include?(name)
          return unless @dropped_tags.empty?

          dispatch_tag(name, token, closing)
        end

        def handle_dropped(name, closing, token)
          if closing
            index = @dropped_tags.rindex(name)
            @dropped_tags.slice!(index..) if index
          elsif !token.match?(%r{/\s*>\z})
            @dropped_tags << name
          end
        end

        # Unknown tags fall through untouched, which is what keeps arbitrary
        # markup from derailing the parse.
        def dispatch_tag(name, token, closing)
          return handle_inline(name, token, closing) if INLINE_STYLES.key?(name)

          dispatch_void(name) || dispatch_structural(name, closing)
        end

        # Tags with no content of their own; a closing form is meaningless.
        def dispatch_void(name)
          case name
          when 'br' then handle_break
          when 'hr' then handle_rule
          end
        end

        def dispatch_structural(name, closing)
          heading = name.match(HEADING)
          return handle_heading(heading[1].to_i, closing) if heading
          return handle_preformatted(closing) if name == 'pre'
          return handle_list(name, closing) if LIST_TAGS.include?(name)
          return handle_list_item(closing) if name == 'li'
          return handle_block(name, closing) if BLOCK_TYPES.key?(name)

          nil
        end

        def handle_break
          # A <br> inside a paragraph is a line break, which this model
          # expresses as the end of one block and the start of the next.
          flush_block
        end

        def handle_rule
          flush_block
          @blocks << ContentBlock.new(type: :rule, segments: [])
        end

        def handle_heading(level, closing)
          flush_block
          @type = closing ? default_type : :heading
          @heading_level = closing ? nil : level
        end

        def handle_preformatted(closing)
          flush_block
          if closing
            @preformatted -= 1 if @preformatted.positive?
            @type = default_type
          else
            @preformatted += 1
            @type = :code
          end
        end

        def handle_list(name, closing)
          flush_block
          if closing
            @lists.pop
          else
            @lists.push({ ordered: name == 'ol', index: 0 })
          end
          @type = default_type
        end

        def handle_list_item(closing)
          flush_block
          if closing
            @type = default_type
            return
          end

          @lists.push({ ordered: false, index: 0 }) if @lists.empty?
          @lists.last[:index] += 1
          @type = :list_item
        end

        def handle_block(name, closing)
          flush_block
          if name == 'blockquote'
            @quote_depth += closing ? -1 : 1
            @quote_depth = 0 if @quote_depth.negative?
            @type = default_type
            return
          end

          @type = closing ? default_type : resolved_block_type(name)
        end

        # A paragraph inside a <blockquote> IS a quote; the type carries that
        # so consumers ask one question (BlockType.quote?) rather than two.
        def resolved_block_type(name)
          type = BLOCK_TYPES.fetch(name)
          type == :paragraph && @quote_depth.positive? ? :quote : type
        end

        def handle_inline(name, token, closing)
          if closing
            index = @styles.rindex { |entry| entry.first == name }
            @styles.slice!(index..) if index
          else
            @styles.push([name, inline_styles_for(name, token)])
          end
        end

        # A link keeps its href so the renderer can show where it points.
        def inline_styles_for(name, token)
          styles = INLINE_STYLES.fetch(name)
          return styles unless styles[:link]

          href = token[/\bhref\s*=\s*"([^"]*)"/i, 1] || token[/\bhref\s*=\s*'([^']*)'/i, 1]
          href = href.to_s.strip
          href.empty? ? {} : { link: href }
        end

        # ----- text -----

        def handle_text(token)
          return unless @dropped_tags.empty?

          text = Shoko::Adapters::Support::HTMLProcessor.decode_entities(token)
          @preformatted.positive? ? append_preformatted(text) : append_prose(text)
        end

        def append_prose(text)
          collapsed = text.gsub(/\s+/, ' ')
          return if collapsed.empty?
          # A gap between tags is only meaningful between existing words.
          return if collapsed == ' ' && @segments.empty?

          @segments << TextSegment.new(text: collapsed, styles: current_styles)
        end

        # Inside <pre> the line structure IS the content, so each source line
        # becomes its own code block and internal spacing is preserved.
        def append_preformatted(text)
          lines = text.split("\n", -1)
          lines.each_with_index do |line, index|
            flush_block if index.positive?
            next if line.empty?

            @segments << TextSegment.new(text: line, styles: current_styles)
          end
        end

        def current_styles
          @styles.reduce({}) { |merged, (_name, styles)| merged.merge(styles) }
        end

        # ----- blocks -----

        def default_type
          @quote_depth.positive? ? :quote : :paragraph
        end

        def flush_block
          segments = @segments
          @segments = []
          return if segments.empty?
          return if @type != :code && segments.all? { |segment| segment.text.strip.empty? }

          @blocks << ContentBlock.new(
            type: @type,
            segments: @type == :code ? segments : trim(segments),
            level: block_level,
            metadata: block_metadata
          )
        end

        def block_level
          return @heading_level.to_i if @type == :heading

          @type == :list_item ? [@lists.length, MAX_LIST_DEPTH].min : 0
        end

        def block_metadata
          metadata = {}
          metadata[:marker] = list_marker if @type == :list_item
          metadata
        end

        def list_marker
          list = @lists.last
          return BULLETS[0] unless list
          return "#{list[:index]}." if list[:ordered]

          BULLETS[(@lists.length - 1) % BULLETS.length]
        end

        # Leading/trailing whitespace belongs to the markup, not the sentence.
        # Not applied to :code, where indentation is content.
        def trim(segments)
          trimmed = segments.dup
          trimmed[0] = restyled(trimmed[0], trimmed[0].text.lstrip)
          last = trimmed.length - 1
          trimmed[last] = restyled(trimmed[last], trimmed[last].text.rstrip)
          trimmed.reject { |segment| segment.text.empty? }
        end

        def restyled(segment, text)
          TextSegment.new(text: text, styles: segment.styles)
        end

        # Drops empty blocks and leading/trailing/duplicate rules, which
        # arbitrary markup produces in quantity.
        def compact(blocks)
          kept = blocks.reject { |block| block.type != :rule && block.segments.empty? }
          kept = collapse_rules(kept)
          kept.pop while kept.last&.type == :rule
          kept
        end

        def collapse_rules(blocks)
          blocks.each_with_object([]) do |block, acc|
            next if block.type == :rule && (acc.empty? || acc.last.type == :rule)

            acc << block
          end
        end
      end
    end
  end
end
