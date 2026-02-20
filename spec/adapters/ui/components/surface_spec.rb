# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Presentation::Ui::Components::Surface do
  let(:terminal) { Shoko::TestSupport::TerminalDouble }
  let(:bounds) { Shoko::Presentation::Ui::Components::Rect.new(x: 1, y: 1, width: 5, height: 3) }

  before { terminal.reset! }

  it 'clips text to the bounds width' do
    surface = described_class.new(terminal)
    surface.write(bounds, 1, 1, 'hello world')
    expect(terminal.writes.last[:text]).to eq('hello')
  end

  it 'ignores writes outside the bounds' do
    surface = described_class.new(terminal)
    surface.write(bounds, 10, 1, 'nope')
    expect(terminal.writes).to be_empty
  end

  it 'applies dim styling when requested' do
    surface = described_class.new(terminal)
    surface.with_dimmed { surface.write(bounds, 1, 1, 'dim') }
    text = terminal.writes.last[:text]
    expect(text).to include(Shoko::Terminal::ANSI::DIM)
    expect(text).to include(Shoko::Terminal::ANSI::RESET)
  end
end
