# frozen_string_literal: true

require_relative '../../../terminal/text_metrics'

module Shoko
  module Adapters
    module Output
      module Formatting
        class FormattingService
          class LineAssembler
            # Wraps tokens into display lines (including inline image placeholders).
            class TextWrapper
              include Shoko::Core::Models

              def initialize(width, image_builder:)
                @width = width.to_i
                @image_builder = image_builder
              end

              def wrap(tokens, metadata:, prefix: nil, continuation_prefix: nil)
                return [] if tokens.empty?

                first_prefix_tokens, continuation_tokens = prefix_tokens(prefix, continuation_prefix)
                state = LineState.new(first_prefix_tokens, continuation_tokens)
                wrapped = []

                tokens.each do |token|
                  process_token(token, state, metadata, wrapped)
                end

                append_final_line(state, metadata, wrapped)
                wrapped
              end

              private

              def prefix_tokens(prefix, continuation_prefix)
                first = Tokenizer.prefix_tokens(prefix)
                continuation = continuation_prefix_value(prefix, continuation_prefix)
                [first, Tokenizer.prefix_tokens(continuation)]
              end

              def continuation_prefix_value(prefix, continuation_prefix)
                return continuation_prefix unless continuation_prefix.nil?

                Tokenizer.prefix_indent(prefix)
              end

              def process_token(token, state, metadata, wrapped)
                return append_inline_image(token[:inline_image], state, metadata, wrapped) if token[:image]
                return append_newline(state, metadata, wrapped) if token[:newline]

                append_text(token, state, metadata, wrapped)
              end

              def append_inline_image(inline, state, metadata, wrapped)
                wrapped << finalize_line(state.tokens, metadata) unless state.tokens.empty?
                wrapped.concat(@image_builder.inline_lines(inline, state.indent_cols))
                state.reset_to_continuation!
              end

              def append_newline(state, metadata, wrapped)
                wrapped << finalize_line(state.tokens, metadata)
                state.reset_to_continuation!
              end

              def append_text(token, state, metadata, wrapped)
                token_width = token_width(token)
                if oversized_token?(token_width, state)
                  append_split_text(token, state, metadata, wrapped)
                  return
                end

                if wrap_needed?(state.width, token_width)
                  wrapped << finalize_line(state.tokens, metadata)
                  state.reset_to_continuation!
                  return if token[:text].strip.empty?
                end

                return if state.tokens.empty? && token[:text].strip.empty?

                state.tokens << token
                state.width += token_width
              end

              def append_split_text(token, state, metadata, wrapped)
                remaining = token[:text].to_s
                styles = token[:styles] || {}

                until remaining.empty?
                  available = @width - state.width
                  if available <= 0
                    wrapped << finalize_line(state.tokens, metadata)
                    state.reset_to_continuation!
                    next
                  end

                  piece = Shoko::Adapters::Output::Terminal::TextMetrics.truncate_to(remaining, available)
                  piece = first_grapheme(remaining) if piece.empty?
                  break if piece.nil? || piece.empty?

                  piece_width = text_width(piece)
                  state.tokens << { text: piece, styles: styles, width: piece_width }
                  state.width += piece_width
                  remaining = drop_prefix(remaining, piece)

                  next if remaining.empty?

                  wrapped << finalize_line(state.tokens, metadata)
                  state.reset_to_continuation!
                end
              end

              def append_final_line(state, metadata, wrapped)
                wrapped << finalize_line(state.tokens, metadata) unless state.tokens.empty?
              end

              def wrap_needed?(current_width, token_width)
                current_width.positive? && current_width + token_width > @width
              end

              def oversized_token?(token_width, state)
                token_width > [@width - state.indent_cols, 1].max
              end

              def first_grapheme(text)
                text.to_s.each_grapheme_cluster do |cluster|
                  return cluster
                end
                ''
              end

              def drop_prefix(text, prefix)
                source = text.to_s
                len = prefix.to_s.bytesize
                source.byteslice(len, source.bytesize - len).to_s
              end

              def finalize_line(tokens, metadata)
                DisplayLine.new(
                  text: line_text(tokens),
                  segments: merge_tokens_into_segments(tokens).reject { |seg| seg.text.empty? },
                  metadata: metadata
                )
              end

              def line_text(tokens)
                tokens.select { |token| token[:text] }.map { |token| token[:text] }.join.rstrip
              end

              def merge_tokens_into_segments(tokens)
                merged = []
                tokens.each do |token|
                  next unless token[:text]

                  styles = token[:styles] || {}
                  if merged.empty? || merged.last.styles != styles
                    merged << TextSegment.new(text: token[:text], styles: styles)
                  else
                    merged[-1] = TextSegment.new(text: merged[-1].text + token[:text], styles: styles)
                  end
                end
                merged
              end

              def text_width(text)
                Shoko::Adapters::Output::Terminal::TextMetrics.visible_length(text.to_s)
              end

              def token_width(token)
                width = token[:width]
                return width unless width.nil?

                text_width(token[:text])
              end

              # Tracks the in-progress wrapped line while streaming tokens.
              class LineState
                attr_accessor :tokens, :width

                def initialize(first_prefix_tokens, continuation_tokens)
                  @continuation_tokens = continuation_tokens
                  @tokens = first_prefix_tokens.dup
                  @width = visible_length(@tokens)
                end

                def indent_cols
                  visible_length(@continuation_tokens)
                end

                def reset_to_continuation!
                  @tokens = @continuation_tokens.dup
                  @width = visible_length(@tokens)
                end

                private

                def visible_length(tokens)
                  tokens
                    .select { |token| token[:text] }
                    .sum do |token|
                      width = token[:width]
                      width.nil? ? Shoko::Adapters::Output::Terminal::TextMetrics.visible_length(token[:text]) : width
                    end
                end
              end
            end
          end
        end
      end
    end
  end
end
