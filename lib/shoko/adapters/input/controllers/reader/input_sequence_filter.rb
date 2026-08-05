# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module Reader
          # Owns mouse-sequence buffering so stale prefixes do not trap real keys.
          class InputSequenceFilter
            def initialize(mouse_handler:, handle_mouse_input:)
              @mouse_handler = mouse_handler
              @handle_mouse_input = handle_mouse_input
              @mouse_input_buffer = nil
            end

            def filter(keys)
              context = { remaining: [], saw_mouse: false, saw_prefix: false }
              keys.each { |token| process_token(token, context) }
              context[:remaining]
            end

            def spurious_post_mouse_key?(token, context)
              (context[:saw_mouse] || context[:saw_prefix]) && token == "\e"
            end

            private

            def process_token(token, context)
              if @mouse_input_buffer
                process_buffered_token(token, context)
              else
                process_unbuffered_token(token, context)
              end
            end

            def process_buffered_token(token, context)
              @mouse_input_buffer << token
              if @mouse_handler.mouse_sequence?(@mouse_input_buffer)
                @handle_mouse_input.call(@mouse_input_buffer)
                @mouse_input_buffer = nil
                context[:saw_mouse] = true
              elsif @mouse_handler.mouse_prefix?(@mouse_input_buffer)
                context[:saw_prefix] = true
              else
                @mouse_input_buffer = nil
                process_unbuffered_token(token, context)
              end
            end

            def process_unbuffered_token(token, context)
              if @mouse_handler.mouse_sequence?(token)
                @handle_mouse_input.call(token)
                context[:saw_mouse] = true
              elsif @mouse_handler.mouse_prefix?(token)
                @mouse_input_buffer = +String(token)
                context[:saw_prefix] = true
              elsif !spurious_post_mouse_key?(token, context)
                context[:remaining] << token
              end
            end
          end
        end
      end
    end
  end
end
