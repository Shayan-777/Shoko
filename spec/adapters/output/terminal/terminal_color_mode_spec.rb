# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Output::Terminal::Terminal do
  let(:input) { instance_double(Shoko::Adapters::Output::Terminal::TerminalInput) }

  before do
    described_class.reset!
    described_class.instance_variable_set(:@input, input)
    described_class.instance_variable_set(:@color_mode, nil)
  end

  after do
    described_class.reset!
  end

  it 'honors explicit SHOKO_COLOR_MODE without querying OSC' do
    allow(input).to receive(:query_default_background).and_raise('should not be called')

    with_env('SHOKO_COLOR_MODE' => 'light', 'SHOKO_ENABLE_OSC_QUERY' => '', 'COLORFGBG' => '') do
      described_class.refresh_color_mode
      expect(described_class.color_mode).to eq(:light)
    end
  end

  it 'uses COLORFGBG before OSC queries when set' do
    allow(input).to receive(:query_default_background).and_raise('should not be called')

    with_env('SHOKO_COLOR_MODE' => '', 'SHOKO_ENABLE_OSC_QUERY' => '', 'COLORFGBG' => '0;15') do
      described_class.refresh_color_mode
      expect(described_class.color_mode).to eq(:light)
    end
  end

  it 'falls back to dark without raising when COLORFGBG has a non-numeric slot (rxvt/urxvt)' do
    allow(input).to receive(:query_default_background).and_raise('should not be called')

    with_env('SHOKO_COLOR_MODE' => '', 'SHOKO_ENABLE_OSC_QUERY' => '', 'COLORFGBG' => 'default;default') do
      expect { described_class.refresh_color_mode }.not_to raise_error
      expect(described_class.color_mode).to eq(:dark)
    end
  end

  it 'still parses a numeric background slot when the foreground slot is non-numeric' do
    allow(input).to receive(:query_default_background).and_raise('should not be called')

    with_env('SHOKO_COLOR_MODE' => '', 'SHOKO_ENABLE_OSC_QUERY' => '', 'COLORFGBG' => 'default;7') do
      described_class.refresh_color_mode
      expect(described_class.color_mode).to eq(:light)
    end
  end

  it 'queries OSC only when explicitly enabled' do
    allow(input).to receive(:query_default_background).and_return([0.1, 0.1, 0.1])

    with_env('SHOKO_COLOR_MODE' => '', 'SHOKO_ENABLE_OSC_QUERY' => '1', 'COLORFGBG' => '') do
      described_class.refresh_color_mode
      expect(described_class.color_mode).to eq(:dark)
    end
  end
end
