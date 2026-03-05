# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Ui::Constants::Themes do
  describe '.canonical_theme' do
    it 'normalizes legacy theme aliases' do
      expect(described_class.canonical_theme(:dark)).to eq(:default)
      expect(described_class.canonical_theme('light')).to eq(:gray)
    end

    it 'returns nil for unknown themes' do
      expect(described_class.canonical_theme(:unknown_theme)).to be_nil
    end
  end

  describe '.available_themes' do
    it 'excludes alias-only entries from user-facing themes' do
      expect(described_class.available_themes).not_to include(:standard)
      expect(described_class.available_themes).to include(:default, :gray, :sepia)
    end
  end

  describe '.color_mode_for' do
    it 'derives light mode for light-oriented themes' do
      expect(described_class.color_mode_for(:gray)).to eq(:light)
      expect(described_class.color_mode_for(:sepia)).to eq(:light)
    end

    it 'derives dark mode for dark-oriented themes' do
      expect(described_class.color_mode_for(:default)).to eq(:dark)
      expect(described_class.color_mode_for(:nord)).to eq(:dark)
    end
  end

  describe '.palette_for' do
    it 'uses dark primary text for the light gray theme' do
      palette = described_class.palette_for(:gray)

      expect(palette.fetch(:primary)).to eq(Shoko::Shared::Terminal::Ansi::BLACK)
    end
  end
end
