# frozen_string_literal: true

require_relative '../../../terminal/text_metrics'

module Shoko
  module Adapters::Output::Formatting
    class FormattingService
      class LineAssembler
        # Turns styled text segments into a stream of wrapping tokens.
        module Tokenizer
          # Pre-frozen common style objects to avoid repeated hash allocations
          EMPTY_STYLES = {}.freeze
          PREFIX_STYLES = { prefix: true }.freeze
          TOKENIZE_CACHE_LIMIT = 2_000
          TOKENIZE_CACHEABLE_SEGMENTS = 200
          TOKENIZE_CACHEABLE_BYTES = 32_768
          TOKENIZE_CACHE_KEY = :shoko_line_assembler_tokenize_cache
          TOKENIZE_CACHE_ORDER_KEY = :shoko_line_assembler_tokenize_cache_order
          TOKENIZE_CACHE_ENABLED_KEY = :shoko_line_assembler_tokenize_cache_enabled
          TOKEN_WIDTH_HINTS_ENABLED_KEY = :shoko_line_assembler_token_width_hints_enabled
          TOKENIZE_CACHE_DISABLED = ENV.fetch('SHOKO_DISABLE_LINE_ASSEMBLER_TOKENIZE_CACHE', '').to_s.strip == '1'
          TOKEN_WIDTH_HINTS_DISABLED = ENV.fetch('SHOKO_DISABLE_LINE_ASSEMBLER_TOKEN_WIDTH_HINTS', '').to_s.strip == '1'

          module_function

          def with_tokenize_cache(enabled:)
            previous = Thread.current[TOKENIZE_CACHE_ENABLED_KEY]
            Thread.current[TOKENIZE_CACHE_ENABLED_KEY] = enabled ? true : false
            yield
          ensure
            Thread.current[TOKENIZE_CACHE_ENABLED_KEY] = previous
          end

          def clear_tokenize_cache
            Thread.current[TOKENIZE_CACHE_KEY] = {}
            Thread.current[TOKENIZE_CACHE_ORDER_KEY] = []
          end

          def with_token_width_hints(enabled:)
            previous = Thread.current[TOKEN_WIDTH_HINTS_ENABLED_KEY]
            Thread.current[TOKEN_WIDTH_HINTS_ENABLED_KEY] = enabled ? true : false
            yield
          ensure
            Thread.current[TOKEN_WIDTH_HINTS_ENABLED_KEY] = previous
          end

          def tokenize_cache_enabled?
            override = Thread.current[TOKENIZE_CACHE_ENABLED_KEY]
            return override unless override.nil?

            !TOKENIZE_CACHE_DISABLED
          end

          def token_width_hints_enabled?
            override = Thread.current[TOKEN_WIDTH_HINTS_ENABLED_KEY]
            return override unless override.nil?

            !TOKEN_WIDTH_HINTS_DISABLED
          end

          def tokenize(segments, image_rendering:, renderable_image_src:)
            segment_list = segments.to_a
            cache = tokenize_cache_for(segment_list, image_rendering)
            cache_key = nil
            unless cache.nil?
              cache_key = tokenize_cache_key(segment_list, token_width_hints_enabled?)
              cached = cache[cache_key]
              return cached unless cached.nil?
            end

            tokens = []

            segment_list.each do |segment|
              styles = segment.styles || {}
              inline = styles[:inline_image] || styles['inline_image']
              if image_rendering && inline_image_token?(inline, renderable_image_src)
                tokens << { image: true, inline_image: inline }
                next
              end

              tokens.concat(tokenize_text(segment.text.to_s, styles))
            end

            cached_tokens = cache_tokenized(cache, cache_key, tokens) if cache
            cached_tokens || tokens
          end

          def prefix_indent(prefix)
            return nil unless prefix

            ' ' * prefix.to_s.length
          end

          def prefix_tokens(prefix)
            return [] if prefix.nil? || prefix.empty?

            [token_from_string(prefix, styles: PREFIX_STYLES)]
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
            return [token_from_string(text, styles: frozen_styles)] if parts.empty?

            parts.map { |part| token_from_string(part, styles: frozen_styles) }
          end

          def token_from_string(text, styles:)
            token = { text: text, styles: freeze_styles(styles) }
            token[:width] = text_width_hint(text) if token_width_hints_enabled?
            token
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

          def tokenize_cache_for(segments, image_rendering)
            return nil unless tokenize_cache_enabled?
            return nil if image_rendering
            return nil unless cacheable_tokenize_input?(segments)

            Thread.current[TOKENIZE_CACHE_KEY] ||= {}
          end
          private_class_method :tokenize_cache_for

          def cacheable_tokenize_input?(segments)
            return false if segments.length > TOKENIZE_CACHEABLE_SEGMENTS

            total_bytes = 0
            segments.each do |segment|
              total_bytes += segment.text.to_s.bytesize
              return false if total_bytes > TOKENIZE_CACHEABLE_BYTES
            end

            true
          end
          private_class_method :cacheable_tokenize_input?

          def tokenize_cache_key(segments, token_width_hints_enabled)
            rolling = 2_166_136_261

            segments.each do |segment|
              rolling = ((rolling * 16_777_619) ^ segment.object_id) & 0xFFFFFFFF_FFFFFFFF
              rolling = ((rolling * 16_777_619) ^ segment.text.to_s.object_id) & 0xFFFFFFFF_FFFFFFFF
              rolling = ((rolling * 16_777_619) ^ (segment.styles || EMPTY_STYLES).object_id) & 0xFFFFFFFF_FFFFFFFF
            end

            [segments.object_id, segments.length, rolling, token_width_hints_enabled ? 1 : 0]
          end
          private_class_method :tokenize_cache_key

          def cache_tokenized(cache, key, tokens)
            return nil if cache.nil? || key.nil?

            order = Thread.current[TOKENIZE_CACHE_ORDER_KEY] ||= []
            unless cache.key?(key)
              order << key
              while order.length > TOKENIZE_CACHE_LIMIT
                oldest = order.shift
                cache.delete(oldest)
              end
            end

            cache[key] = tokens.map { |token| token.frozen? ? token : token.dup.freeze }.freeze
            cache[key]
          end
          private_class_method :cache_tokenized

          def text_width_hint(text)
            Shoko::Adapters::Output::Terminal::TextMetrics.visible_length(text.to_s)
          end
          private_class_method :text_width_hint
        end
      end
    end
  end
end
