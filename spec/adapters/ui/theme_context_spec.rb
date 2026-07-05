# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Ui::ThemeContext do
  after do
    described_class.apply!(theme_id: :default)
  end

  describe '.resolve' do
    it 'returns canonical theme, derived color mode, and palette' do
      context = described_class.resolve(theme_id: :dark)

      expect(context.theme_id).to eq(:default)
      expect(context.color_mode).to eq(:dark)
      expect(context.palette).to eq(Shoko::Adapters::Ui::Constants::Themes.palette_for(:default))
      expect(context.ui_tokens).to include(:highlight_bg, :annotation_panel_bg)
    end
  end

  describe '.apply!' do
    it 'applies mode and render palette for the selected theme' do
      context = described_class.apply!(theme_id: :sepia)

      expect(context.color_mode).to eq(:light)
      expect(Shoko::Adapters::Ui::Constants::Ui::HIGHLIGHT_BG_ACTIVE)
        .to eq(Shoko::Adapters::Ui::Constants::Ui::HIGHLIGHT_BG_LIGHT)
      expect(Shoko::Adapters::Ui::Components::RenderStyle.palette)
        .to eq(Shoko::Adapters::Ui::Constants::Themes.palette_for(:sepia))
    end
  end
end
