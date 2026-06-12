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
            @resize_pending = false
            @wake_reader, @wake_writer = IO.pipe
          end

          def size
            update_size_cache if cache_expired?
            [@size_cache[:height], @size_cache[:width]]
          end

          def setup_console
            $stdout.sync = true
            @console = resolve_console
            @console.raw!
          end

          def cleanup_console
            @console&.cooked!
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
            no_input_token
          end

          def read_key_blocking(timeout: nil)
            deadline = timeout_deadline(timeout)
            loop do
              key = read_key
              return key if key

              wait = next_key_wait(deadline)
              return nil if wait == :expired
              # A resize wake-up returns one spurious nil so the caller's loop
              # can notice the pending resize instead of blocking on input.
              return nil if block_for_input(wait) == :woke
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
            return nil unless @input.tty?

            @output.print(OSC_QUERY_BG)
            @output.flush
            response = read_osc_response(timeout: timeout)
            parse_osc_rgb(response)
          end

          def setup_signal_handlers(&cleanup_callback)
            %w[INT TERM].each do |signal|
              trap(signal) do
                cleanup_callback&.call
                exit(0)
              end
            end
            trap('WINCH') { signal_resize! }
          end

          # Wakes any blocked key read via the self-pipe without queuing input;
          # the read returns one spurious nil so the caller's loop can notice
          # pending work (a resize, a worker-posted render request). Safe from
          # trap context and worker threads (nonblocking pipe write only).
          def wake!
            @wake_writer.write_nonblock('w', exception: false)
            nil
          end

          # Marks a pending terminal resize and wakes any blocked key read.
          # Called from the WINCH trap.
          def signal_resize!
            @resize_pending = true
            wake!
          end

          # True exactly once per resize burst. Consuming also invalidates the
          # size cache so the very next size query reads the real winsize
          # instead of a value cached before the resize.
          def consume_resize_event?
            return false unless @resize_pending

            @resize_pending = false
            @size_cache = { width: nil, height: nil, checked_at: nil }
            true
          end

          def drain_input(timeout: 0.05)
            return nil unless @input.tty?

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
            console = IO.console
            console ||= @input if @input.respond_to?(:tty?) && @input.tty?
            return console.winsize if console.respond_to?(:winsize)

            default_dimensions
          rescue Shoko::Error, IOError, SystemCallError, NoMethodError
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

            if @input.tty?
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
            no_input_token
          end

          def read_osc_response(timeout:)
            deadline = monotonic_now + timeout.to_f
            buffer = +''.b

            loop do
              ready = wait_for_osc_input(deadline)
              return nil unless ready

              buffer << read_osc_chunk
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

          def no_input_token
            nil
          end

          def timeout_deadline(timeout)
            timeout ? monotonic_now + timeout.to_f : nil
          end

          def next_key_wait(deadline)
            now = monotonic_now
            remaining = deadline ? (deadline - now) : nil
            return :expired if remaining && remaining <= 0

            pending = @decoder.pending_timeout(now: now)
            pending && remaining ? [pending, remaining].min : (pending || remaining)
          end

          # Blocks until input arrives, the wait expires, or the self-pipe
          # wakes us (terminal resize). Returns :woke for the wake case.
          # Non-IO inputs (test doubles) keep the plain wait_readable path —
          # IO.select only accepts real IO objects.
          def block_for_input(wait)
            return if wait && wait <= 0
            return legacy_wait_for_input(wait) unless @input.is_a?(IO)

            ready = IO.select([@input, @wake_reader], nil, nil, wait)
            return unless ready

            :woke if drain_wake_pipe?(ready.first)
          end

          def legacy_wait_for_input(wait)
            wait.nil? ? @input.wait_readable : @input.wait_readable(wait)
            nil
          end

          def drain_wake_pipe?(ready_sources)
            return false unless ready_sources.include?(@wake_reader)

            # exception: false returns :wait_readable / nil instead of raising,
            # so the pipe drains without rescue-as-flow-control.
            loop do
              break unless @wake_reader.read_nonblock(64, exception: false).is_a?(String)
            end
            true
          end

          def wait_for_osc_input(deadline)
            remaining = deadline - monotonic_now
            return nil if remaining <= 0

            @input.wait_readable(remaining)
          end

          def read_osc_chunk
            @input.read_nonblock(READ_CHUNK_BYTES)
          end

          def monotonic_now
            Process.clock_gettime(Process::CLOCK_MONOTONIC)
          end
        end
      end
    end
  end
end
