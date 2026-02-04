# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Output::Terminal::TerminalService do
  let(:terminal) { Shoko::Adapters::Output::Terminal::Terminal }
  let(:ui_constants) { Shoko::Adapters::Output::Ui::Constants::UI }

  before do
    allow(terminal).to receive(:setup)
    allow(terminal).to receive(:cleanup)
    allow(terminal).to receive(:color_mode).and_return(:dark)
    allow(ui_constants).to receive(:apply_color_mode)
  end

  it 'cleans up only once when cleanup is called multiple times' do
    service = described_class.new

    service.setup
    service.cleanup
    service.cleanup

    expect(terminal).to have_received(:cleanup).once
  end

  it 'does not force cleanup when never setup' do
    service = described_class.new

    service.force_cleanup

    expect(terminal).not_to have_received(:cleanup)
  end

  it 'force cleans up once after setup' do
    service = described_class.new

    service.setup
    service.force_cleanup
    service.force_cleanup

    expect(terminal).to have_received(:cleanup).once
  end
end
