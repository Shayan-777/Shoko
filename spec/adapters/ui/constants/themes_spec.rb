# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Ui::Constants::Themes do
  describe '.available_themes' do
    it 'excludes alias-only entries from user-facing themes' do
      expect(described_class.available_themes).not_to include(:standard, :dark, :light)
      expect(described_class.available_themes).to include(:default, :gray, :sepia)
    end

    it 'can expose legacy aliases when explicitly requested' do
      expect(described_class.available_themes(include_aliases: true)).to include(:standard, :dark, :light)
    end
  end

  describe '.color_mode_for' do
    it 'derives light mode for light-oriented themes' do
      expect(described_class.color_mode_for(:gray)).to eq(:light)
      expect(described_class.color_mode_for(:sepia)).to eq(:light)
      expect(described_class.color_mode_for(:light)).to eq(:light)
    end

    it 'derives dark mode for dark-oriented themes' do
      expect(described_class.color_mode_for(:default)).to eq(:dark)
      expect(described_class.color_mode_for(:nord)).to eq(:dark)
      expect(described_class.color_mode_for(:standard)).to eq(:dark)
    end
  end

  describe '.palette_for' do
    it 'uses dark primary text for the light gray theme on 16-color terminals' do
      palette = described_class.palette_for(:gray, truecolor: false)

      expect(palette.fetch(:primary)).to eq(Shoko::Shared::Terminal::Ansi::BLACK)
    end

    it 'uses 24-bit palettes on truecolor terminals' do
      palette = described_class.palette_for(:sepia, truecolor: true)

      expect(palette.fetch(:primary)).to start_with("\e[38;2;")
    end

    it 'keeps the terminal default foreground for the default truecolor theme' do
      palette = described_class.palette_for(:default, truecolor: true)

      expect(palette.fetch(:primary)).to eq(Shoko::Shared::Terminal::Ansi::DEFAULT_FG)
      expect(palette.fetch(:heading)).to start_with("\e[38;2;")
    end

    it 'provides a code background for themes that shade code blocks' do
      expect(described_class.palette_for(:gruvbox, truecolor: true)[:code_bg]).to start_with("\e[48;2;")
      expect(described_class.palette_for(:gruvbox, truecolor: false)[:code_bg]).to be_nil
    end
  end
end
