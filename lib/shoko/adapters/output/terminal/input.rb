# frozen_string_literal: true

require 'io/console'
require_relative 'constants/terminal_defaults'
require_relative 'input/decoder'

module Shoko
  module Adapters
    module Output
      module Terminal
        # TerminalInput encapsulates input reading, console modes, and size queries.
        class TerminalInput
          SIZE_CACHE_INTERVAL = 0.5
          READ_CHUNK_BYTES = 4096
          OSC_QUERY_BG = "\e]11;?\a"
          OSC_TERMINATOR_BEL = "\a"
          OSC_TERMINATOR_ST = "\e\\"
          OSC_BG_PATTERN = %r{\e\]11;rgb:([0-9a-fA-F]{1,4})/([0-9a-fA-F]{1,4})/([0-9a-fA-F]{1,4})}

          def initialize(input: $stdin, output: $stdout, esc_timeout: Decoder::DEFAULT_ESC_TIMEOUT,
                         sequence_timeout: Decoder::DEFAULT_SEQUENCE_TIMEOUT)
            @console = nil
            @size_cache = { width: nil, height: nil, checked_at: nil }
            @input = input
            @output = output
            @decoder = Decoder.new(esc_timeout: esc_timeout, sequence_timeout: sequence_timeout)
          end

          def size
            update_size_cache if cache_expired?
            [@size_cache[:height], @size_cache[:width]]
          end

          def setup_console
            $stdout.sync = true
            @console = resolve_console
            @console.raw! if @console.respond_to?(:raw!)
          end

          def cleanup_console
            @console.cooked! if @console.respond_to?(:cooked!)
            @console = nil
          end

          def with_raw_console(&)
            console = resolve_console
            console.raw(&)
          end

          def read_key
            with_raw_console do
              pump_input
              @decoder.next_token(now: monotonic_now)
            end
          rescue IO::WaitReadable, EOFError
            nil
          end

          def read_key_blocking(timeout: nil)
            deadline = timeout ? monotonic_now + timeout.to_f : nil
            loop do
              key = read_key
              return key if key

              now = monotonic_now
              remaining = deadline ? (deadline - now) : nil
              return nil if remaining && remaining <= 0

              pending = @decoder.pending_timeout(now: now)
              wait = if pending && remaining
                       [pending, remaining].min
                     else
                       pending || remaining
                     end

              if wait
                next if wait <= 0

                @input.wait_readable(wait)
              else
                @input.wait_readable
              end
            end
          end

          # Mouse support
          def enable_mouse
            # 1003 enables any-motion reporting so hover can drive popup highlighting.
            @output.print "\e[?1002h\e[?1003h\e[?1006h"
            @output.flush
          end

          def disable_mouse
            @output.print "\e[?1002l\e[?1003l\e[?1006l"
            @output.flush
          end

          def read_input_with_mouse(timeout: nil)
            read_key_blocking(timeout: timeout)
          end

          def query_default_background(timeout: 0.2)
            return nil unless @input.respond_to?(:tty?) && @input.tty?

            @output.print(OSC_QUERY_BG)
            @output.flush
            response = read_osc_response(timeout: timeout)
            parse_osc_rgb(response)
          rescue StandardError
            nil
          end

          def setup_signal_handlers(&cleanup_callback)
            %w[INT TERM].each do |signal|
              trap(signal) do
                cleanup_callback&.call
                exit(0)
              end
            end
          end

          def drain_input(timeout: 0.05)
            return nil unless @input.respond_to?(:tty?) && @input.tty?

            deadline = monotonic_now + timeout.to_f
            loop do
              remaining = deadline - monotonic_now
              break if remaining <= 0

              ready = @input.wait_readable(remaining)
              break unless ready

              begin
                @input.read_nonblock(READ_CHUNK_BYTES)
              rescue IO::WaitReadable
                next
              rescue EOFError
                break
              end
            end
          rescue StandardError
            nil
          end

          private

          def cache_expired?
            now = Time.now
            checked = @size_cache[:checked_at]
            checked.nil? || now - checked > SIZE_CACHE_INTERVAL
          end

          def update_size_cache
            h, w = fetch_terminal_size
            @size_cache = { width: w, height: h, checked_at: Time.now }
          end

          def fetch_terminal_size
            IO.console.winsize
          rescue StandardError
            default_dimensions
          end

          def default_dimensions
            [Adapters::Output::Terminal::TerminalDefaults::DEFAULT_ROWS,
             Adapters::Output::Terminal::TerminalDefaults::DEFAULT_COLUMNS]
          end

          def resolve_console
            return @console if @console

            console = IO.console
            if console
              @console = console
              return console
            end

            if @input.respond_to?(:tty?) && @input.tty? && @input.respond_to?(:raw)
              @console = @input
              return @input
            end

            raise Shoko::TerminalUnavailableError
          end

          def pump_input
            loop do
              chunk = @input.read_nonblock(READ_CHUNK_BYTES)
              @decoder.feed(chunk)
            end
          rescue IO::WaitReadable, EOFError
            nil
          end

          def read_osc_response(timeout:)
            deadline = monotonic_now + timeout.to_f
            buffer = +''.b

            loop do
              remaining = deadline - monotonic_now
              return nil if remaining <= 0

              ready = @input.wait_readable(remaining)
              return nil unless ready

              chunk = @input.read_nonblock(READ_CHUNK_BYTES)
              buffer << chunk
              break if buffer.include?(OSC_TERMINATOR_BEL) || buffer.include?(OSC_TERMINATOR_ST)
            rescue IO::WaitReadable
              next
            rescue EOFError
              break
            end

            buffer
          end

          def parse_osc_rgb(response)
            return nil unless response

            match = response.match(OSC_BG_PATTERN)
            return nil unless match

            match.captures.map { |hex| normalize_component(hex) }
          end

          def normalize_component(hex)
            value = hex.to_i(16)
            max = hex.length > 2 ? 65_535.0 : 255.0
            value / max
          end

          def monotonic_now
            Process.clock_gettime(Process::CLOCK_MONOTONIC)
          rescue StandardError
            Time.now.to_f
          end
        end
      end
    end
  end
end
