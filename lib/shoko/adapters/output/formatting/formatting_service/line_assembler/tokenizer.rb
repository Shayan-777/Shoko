# frozen_string_literal: true

module Shoko
  module Adapters::Output::Formatting
    class FormattingService
      class LineAssembler
        # Turns styled text segments into a stream of wrapping tokens.
        module Tokenizer
          # Pre-frozen common style objects to avoid repeated hash allocations
          EMPTY_STYLES = {}.freeze
          PREFIX_STYLES = { prefix: true }.freeze

          module_function

          def tokenize(segments, image_rendering:, renderable_image_src:)
            tokens = []

            segments.to_a.each do |segment|
              styles = segment.styles || {}
              inline = styles[:inline_image] || styles['inline_image']
              if image_rendering && inline_image_token?(inline, renderable_image_src)
                tokens << { image: true, inline_image: inline }
                next
              end

              tokens.concat(tokenize_text(segment.text.to_s, styles))
            end

            tokens
          end

          def prefix_indent(prefix)
            return nil unless prefix

            ' ' * prefix.to_s.length
          end

          def prefix_tokens(prefix)
            return [] if prefix.nil? || prefix.empty?

            [{ text: prefix, styles: PREFIX_STYLES }]
          end

          def tokenize_text(text, styles)
            return [] if text.empty?

            return split_token(text, styles) unless text.include?("\n")

            tokenize_with_newlines(text, styles)
          end

          def tokenize_with_newlines(text, styles)
            tokens = []
            text.split(/(\n)/).each do |piece|
              if piece == "\n"
                tokens << { newline: true }
              elsif !piece.empty?
                tokens.concat(split_token(piece, styles))
              end
            end
            tokens
          end

          def split_token(text, styles)
            return [] if text.empty?

            parts = text.scan(/\S+\s*/)
            # Freeze styles once and reuse for all tokens from this segment
            frozen_styles = freeze_styles(styles)
            return [{ text: text, styles: frozen_styles }] if parts.empty?

            parts.map { |part| { text: part, styles: frozen_styles } }
          end

          def token_from_string(text, styles:)
            { text: text, styles: freeze_styles(styles) }
          end

          def freeze_styles(styles)
            return EMPTY_STYLES if styles.empty?
            return styles if styles.frozen?

            styles.freeze
          end

          def inline_image_token?(inline, renderable_image_src)
            src = image_src(inline)
            renderable_image_src.call(src)
          rescue StandardError
            false
          end
          private_class_method :inline_image_token?

          def image_src(inline)
            return nil unless inline.is_a?(Hash)

            inline[:src] || inline['src']
          end
          private_class_method :image_src
        end
      end
    end
  end
end
