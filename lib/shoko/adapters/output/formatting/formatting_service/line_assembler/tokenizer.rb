# frozen_string_literal: true

require 'shoko/shared/thread_local_scope'
require 'shoko/adapters/output/terminal/text_metrics'

module Shoko
  module Adapters
    module Output
      module Formatting
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
              RUNTIME_CONFIG_KEY = :shoko_line_assembler_runtime_config

              module_function

              def with_runtime_config(config:, &)
                Shoko::Shared::ThreadLocalScope.with(key: RUNTIME_CONFIG_KEY, value: config, &)
              end

              def configure_runtime_config!(runtime_config:)
                @configured_runtime_config = runtime_config
              end

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

                !runtime_config.line_assembler_tokenize_cache_disabled?
              end

              def token_width_hints_enabled?
                override = Thread.current[TOKEN_WIDTH_HINTS_ENABLED_KEY]
                return override unless override.nil?

                !runtime_config.line_assembler_token_width_hints_disabled?
              end

              def tokenize(segments, image_rendering:, renderable_image_src:)
                segment_list = segments.to_a
                cache, cache_key = tokenize_cache_entry(segment_list, image_rendering)
                cached = cache && cache[cache_key]
                return cached unless cached.nil?

                tokens = build_tokens(
                  segment_list,
                  image_rendering: image_rendering,
                  renderable_image_src: renderable_image_src
                )
                cache_tokenized(cache, cache_key, tokens) || tokens
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
              end
              private_class_method :inline_image_token?

              def image_src(inline)
                return nil unless inline.is_a?(Hash)

                inline[:src]
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

              def tokenize_cache_entry(segment_list, image_rendering)
                cache = tokenize_cache_for(segment_list, image_rendering)
                cache_key = cache && tokenize_cache_key(segment_list, token_width_hints_enabled?)
                [cache, cache_key]
              end
              private_class_method :tokenize_cache_entry

              def build_tokens(segment_list, image_rendering:, renderable_image_src:)
                segment_list.each_with_object([]) do |segment, tokens|
                  append_segment_tokens(
                    tokens,
                    segment,
                    image_rendering: image_rendering,
                    renderable_image_src: renderable_image_src
                  )
                end
              end
              private_class_method :build_tokens

              def append_segment_tokens(tokens, segment, image_rendering:, renderable_image_src:)
                styles = segment.styles || {}
                inline = styles[:inline_image]
                if image_rendering && inline_image_token?(inline, renderable_image_src)
                  tokens << { image: true, inline_image: inline }
                else
                  tokens.concat(tokenize_text(segment.text.to_s, styles))
                end
              end
              private_class_method :append_segment_tokens

              def text_width_hint(text)
                Shoko::Adapters::Output::Terminal::TextMetrics.visible_length(text.to_s)
              end
              private_class_method :text_width_hint

              def runtime_config
                config = Thread.current[RUNTIME_CONFIG_KEY]
                config ||= @configured_runtime_config
                return config if config

                raise Shoko::ConfigurationError, 'LineAssembler::Tokenizer runtime_config is not configured'
              end
              private_class_method :runtime_config
            end
          end
        end
      end
    end
  end
end
