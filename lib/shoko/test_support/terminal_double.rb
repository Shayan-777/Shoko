# frozen_string_literal: true

require_relative '../adapters/output/terminal/output'

module Shoko
  # Test-only helpers and doubles for terminal interactions.
  module TestSupport
    # Lightweight replacement for the production Terminal facade that keeps
    # tests deterministic and side-effect free. All terminal operations become
    # in-memory recordings so specs can make assertions without touching an
    # actual TTY.
    class TerminalDouble
      ANSI = Shoko::Adapters::Output::Terminal::TerminalOutput::ANSI

      class << self
        attr_accessor :default_height, :default_width

        def reset!
          @writes = []
          @printed = []
          @moves = []
          @clears = []
          @mouse_events = []
          @input_queue = Queue.new
          @default_height = 24
          @default_width = 80
        end

        def writes
          @writes ||= []
        end

        def printed
          @printed ||= []
        end

        def moves
          @moves ||= []
        end

        def clears
          @clears ||= []
        end

        def mouse_events
          @mouse_events ||= []
        end

        def push_input(*keys)
          ensure_input_queue
          keys.flatten.each { |k| @input_queue << k }
        end

        def drain_input
          ensure_input_queue
          drained = []
          loop do
            drained << @input_queue.pop(true)
          rescue ThreadError
            break
          end
          drained
        end

        def size=(tuple)
          @default_height, @default_width = tuple
        end

        def size
          [@default_height || 24, @default_width || 80]
        end

        def setup
          @setup_calls = setup_calls + 1
        end

        def cleanup
          @cleanup_calls = cleanup_calls + 1
        end

        def setup_calls
          @setup_calls ||= 0
        end

        def cleanup_calls
          @cleanup_calls ||= 0
        end

        def start_frame(**_kwargs)
          # no-op, but record for assertions if needed
          @frame_started = true
        end

        def end_frame
          @frame_started = false
        end

        def frame_started?
          !!@frame_started
        end

        def clear
          clears << :clear
        end

        def move(row, col)
          moves << [row, col]
        end

        def write(row, col, text)
          writes << { row:, col:, text: text.to_s }
        end

        def write_differential(row, col, text)
          write(row, col, text)
        end

        def clear_buffer_cache
          # Nothing cached in the double; keep interface parity.
        end

        def batch_write
          yield if block_given?
        end

        def print(str)
          printed << str.to_s
        end

        def flush
          # no-op
        end

        def enable_mouse
          mouse_events << :enabled
        end

        def disable_mouse
          mouse_events << :disabled
        end

        def read_key
          pop_key(non_block: true)
        end

        def read_key_blocking(timeout: nil)
          pop_key(timeout: timeout || 0.1)
        end

        def read_input_with_mouse(timeout: nil)
          read_key_blocking(timeout: timeout)
        end

        private

        def ensure_input_queue
          @ensure_input_queue ||= Queue.new
        end

        def pop_key(non_block: false, timeout: nil)
          ensure_input_queue
          if non_block
            @input_queue.pop(true)
          elsif timeout
            @input_queue.pop(timeout: timeout)
          else
            @input_queue.pop
          end
        end
      end
    end

    TerminalDouble.reset!
  end
end
