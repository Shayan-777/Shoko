# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Ui::Components::MenuDesign::StatusRenderer do
  include MenuScreenRenderHelpers

  let(:terminal) { Shoko::TestSupport::TerminalDouble }
  let(:surface) { Shoko::Adapters::Ui::Components::Surface.new(terminal) }
  let(:bounds) { Shoko::Adapters::Ui::Components::Rect.new(x: 1, y: 1, width: 170, height: 40) }

  before { terminal.reset! }

  it 'right-aligns status text within the provided content width' do
    described_class.new(surface, bounds).render_status(
      row: 8,
      indent: 49,
      width: 72,
      left: 'Found 180 books',
      right: '✓ Loaded 180 books from cache'
    )

    writes = terminal.writes
    right = writes.find { |entry| strip_ansi(entry[:text]).include?('Loaded 180 books from cache') }

    expect(right).not_to be_nil

    right_width = Shoko::Shared::Terminal::TextMetrics.visible_length(strip_ansi(right[:text]))
    right_edge = right[:col] + right_width - 1
    expect(right_edge).to be <= (49 + 72 - 1)
  end
end
