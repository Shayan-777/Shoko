# frozen_string_literal: true

require 'spec_helper'
require 'stringio'

RSpec.describe Shoko::Adapters::Output::Terminal::TerminalInput do
  it 'enables and disables any-motion mouse tracking sequences' do
    output = StringIO.new
    input = StringIO.new
    terminal_input = described_class.new(input: input, output: output)

    terminal_input.enable_mouse
    terminal_input.disable_mouse

    data = output.string
    expect(data).to include("\e[?1002h")
    expect(data).to include("\e[?1003h")
    expect(data).to include("\e[?1006h")
    expect(data).to include("\e[?1002l")
    expect(data).to include("\e[?1003l")
    expect(data).to include("\e[?1006l")
  end

  it 'falls back to default dimensions when no console is available' do
    output = StringIO.new
    input = StringIO.new
    terminal_input = described_class.new(input: input, output: output)

    allow(IO).to receive(:console).and_return(nil)

    expect(terminal_input.size).to eq([
                                        Shoko::Adapters::Output::Terminal::TerminalDefaults::DEFAULT_ROWS,
                                        Shoko::Adapters::Output::Terminal::TerminalDefaults::DEFAULT_COLUMNS
                                      ])
  end
end
