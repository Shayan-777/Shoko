# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        # Reopened here (defined in mouseable_reader.rb, which requires this file
        # after the class body so the nesting resolves).
        class MouseableReader
          # Owns mouse-sequence buffering and filtering so stale prefixes do not trap real keys.
          class InputSequenceFilter
            def initialize(mouse_handler:, handle_mouse_input:)
              @mouse_handler = mouse_handler
              @handle_mouse_input = handle_mouse_input
              @mouse_input_buffer = nil
            end

            def filter(keys)
              ctx = { remaining: [], saw_mouse: false, saw_prefix: false }
              keys.each { |token| process_token(token, ctx) }
              ctx[:remaining]
            end

            def spurious_post_mouse_key?(token, ctx)
              (ctx[:saw_mouse] || ctx[:saw_prefix]) && token == "\e"
            end

            private

            def process_token(token, ctx)
              if @mouse_input_buffer
                process_buffered_token(token, ctx)
              else
                process_unbuffered_token(token, ctx)
              end
            end

            def process_buffered_token(token, ctx)
              @mouse_input_buffer << token

              if @mouse_handler.mouse_sequence?(@mouse_input_buffer)
                @handle_mouse_input.call(@mouse_input_buffer)
                @mouse_input_buffer = nil
                ctx[:saw_mouse] = true
              elsif @mouse_handler.mouse_prefix?(@mouse_input_buffer)
                ctx[:saw_prefix] = true
              else
                @mouse_input_buffer = nil
                process_unbuffered_token(token, ctx)
              end
            end

            def process_unbuffered_token(token, ctx)
              if @mouse_handler.mouse_sequence?(token)
                @handle_mouse_input.call(token)
                ctx[:saw_mouse] = true
              elsif @mouse_handler.mouse_prefix?(token)
                @mouse_input_buffer = String(token)
                ctx[:saw_prefix] = true
              elsif spurious_post_mouse_key?(token, ctx)
                nil
              else
                ctx[:remaining] << token
              end
            end
          end
        end
      end
    end
  end
end
