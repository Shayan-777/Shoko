# frozen_string_literal: true

require 'spec_helper'
require 'shoko/adapters/ui/components/ui/spinner'

RSpec.describe Shoko::Adapters::Ui::Components::Ui::Spinner do
  describe '.glyph' do
    it 'advances one frame per FRAME_SECONDS and wraps around' do
      frames = described_class::BRAILLE_FRAMES
      allow(described_class).to receive(:ascii_icons?).and_return(false)

      expect(described_class.glyph(0.0)).to eq(frames[0])
      expect(described_class.glyph(described_class::FRAME_SECONDS)).to eq(frames[1])
      expect(described_class.glyph(described_class::FRAME_SECONDS * frames.length)).to eq(frames[0])
    end

    it 'uses ASCII frames when SHOKO_ASCII_ICONS is enabled' do
      allow(described_class).to receive(:ascii_icons?).and_return(true)

      expect(described_class::ASCII_FRAMES).to include(described_class.glyph(0.0))
    end
  end
end
