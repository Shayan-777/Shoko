# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Output::Terminal::TerminalSessionAdapter do
  let(:terminal_service) { instance_double('TerminalService', setup: nil, cleanup: nil, size: [24, 80]) }
  subject(:adapter) { described_class.new(terminal_service: terminal_service) }

  it 'delegates setup/cleanup/size to terminal service' do
    expect(adapter.setup).to be_nil
    expect(adapter.cleanup).to be_nil
    expect(adapter.size).to eq([24, 80])

    expect(terminal_service).to have_received(:setup)
    expect(terminal_service).to have_received(:cleanup)
    expect(terminal_service).to have_received(:size)
  end
end
