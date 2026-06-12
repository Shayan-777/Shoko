# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require 'timeout'

RSpec.describe Shoko::Adapters::Output::Terminal::TerminalInput do
  describe 'resize wake-up (SIGWINCH)' do
    def build_terminal_input
      input_reader, input_writer = IO.pipe
      terminal_input = described_class.new(input: input_reader, output: StringIO.new)
      # No real console in the spec environment: read keys straight off the pipe.
      allow(terminal_input).to receive(:with_raw_console) { |&block| block.call }
      [terminal_input, input_reader, input_writer]
    end

    it 'wakes a blocked key read and reports the pending resize exactly once' do
      terminal_input, input_reader, input_writer = build_terminal_input

      result = Queue.new
      reader_thread = Thread.new { result << terminal_input.read_key_blocking(timeout: nil) }
      sleep 0.05

      terminal_input.signal_resize!

      expect(Timeout.timeout(2) { result.pop }).to be_nil
      expect(terminal_input.consume_resize_event?).to be(true)
      expect(terminal_input.consume_resize_event?).to be(false)
    ensure
      reader_thread&.kill
      input_reader&.close
      input_writer&.close
    end

    it 'invalidates the size cache when the resize is consumed' do
      terminal_input, input_reader, input_writer = build_terminal_input

      console = instance_double(IO)
      allow(console).to receive(:winsize).and_return([24, 80], [50, 200])
      allow(IO).to receive(:console).and_return(console)

      expect(terminal_input.size).to eq([24, 80])
      # Within the cache interval the stale size would normally be served.
      expect(terminal_input.size).to eq([24, 80])

      terminal_input.signal_resize!
      expect(terminal_input.consume_resize_event?).to be(true)

      expect(terminal_input.size).to eq([50, 200])
    ensure
      input_reader&.close
      input_writer&.close
    end

    it 'still delivers real keys after a resize wake-up' do
      terminal_input, input_reader, input_writer = build_terminal_input

      terminal_input.signal_resize!
      expect(terminal_input.read_key_blocking(timeout: 0.2)).to be_nil
      terminal_input.consume_resize_event?

      input_writer.write('x')
      expect(Timeout.timeout(2) { terminal_input.read_key_blocking(timeout: nil) }).to eq('x')
    ensure
      input_reader&.close
      input_writer&.close
    end

    it 'wakes a blocked key read via wake! without marking a resize' do
      terminal_input, input_reader, input_writer = build_terminal_input

      result = Queue.new
      reader_thread = Thread.new { result << terminal_input.read_key_blocking(timeout: nil) }
      sleep 0.05

      terminal_input.wake!

      expect(Timeout.timeout(2) { result.pop }).to be_nil
      expect(terminal_input.consume_resize_event?).to be(false)
    ensure
      reader_thread&.kill
      input_reader&.close
      input_writer&.close
    end

    it 'installs a WINCH trap through setup_signal_handlers' do
      terminal_input, input_reader, input_writer = build_terminal_input
      previous = trap('WINCH', 'DEFAULT')

      begin
        terminal_input.setup_signal_handlers { nil }
        Process.kill('WINCH', Process.pid)
        Timeout.timeout(2) { sleep 0.01 until terminal_input.consume_resize_event? }
      ensure
        trap('WINCH', previous || 'DEFAULT')
        input_reader&.close
        input_writer&.close
      end
    end
  end
end
