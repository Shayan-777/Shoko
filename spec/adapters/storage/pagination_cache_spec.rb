# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Storage::PaginationCache do
  describe '.layout_key' do
    it 'includes layout variant and image mode in generated keys' do
      key = described_class.layout_key(120, 40, :single, :normal, kitty_images: true, layout_variant: :sidebar)

      expect(key).to eq('120x40_single_normal_img1_sidebar')
    end
  end

  describe '.parse_layout_key' do
    it 'parses keys with explicit layout variants' do
      parsed = described_class.parse_layout_key('120x40_single_normal_img0_sidebar')

      expect(parsed).to include(
        width: 120,
        height: 40,
        view_mode: :single,
        line_spacing: :normal,
        kitty_images: false,
        layout_variant: :sidebar
      )
    end

    it 'defaults to :base for legacy keys without layout variant' do
      parsed = described_class.parse_layout_key('120x40_single_normal_img0')

      expect(parsed).to include(layout_variant: :base)
    end
  end
end
