# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Ui::Components::Ui::ListWindowing do
  describe '.scrollbar_thumb' do
    it 'sizes the thumb to the visible share of the list' do
      thumb = described_class.scrollbar_thumb(total: 20, visible: 5, scroll: 0)

      expect(thumb[:size]).to eq(1)
      expect(thumb[:start]).to eq(0)
    end

    it 'moves the thumb proportionally with the scroll offset' do
      top = described_class.scrollbar_thumb(total: 20, visible: 5, scroll: 0)
      bottom = described_class.scrollbar_thumb(total: 20, visible: 5, scroll: 15)

      expect(top[:start]).to eq(0)
      expect(bottom[:start] + bottom[:size]).to eq(5)
    end

    it 'fills the track when everything is visible' do
      thumb = described_class.scrollbar_thumb(total: 3, visible: 5, scroll: 0)

      expect(thumb).to eq(size: 5, start: 0)
    end

    it 'scales the thumb onto a taller track than the visible item count' do
      thumb = described_class.scrollbar_thumb(total: 10, visible: 5, scroll: 0, track_rows: 10)

      expect(thumb[:size]).to eq(5)
      expect(thumb[:start]).to eq(0)
    end

    it 'never sizes the thumb below one row' do
      thumb = described_class.scrollbar_thumb(total: 1_000, visible: 3, scroll: 0)

      expect(thumb[:size]).to eq(1)
    end
  end

  describe '.scroll_to_reveal' do
    it 'keeps the scroll put while the index is inside the window' do
      expect(described_class.scroll_to_reveal(3, scroll: 2, visible: 4, total: 10)).to eq(2)
    end

    it 'scrolls up to an index above the window' do
      expect(described_class.scroll_to_reveal(1, scroll: 4, visible: 4, total: 10)).to eq(1)
    end

    it 'scrolls down just far enough to reveal an index below the window' do
      expect(described_class.scroll_to_reveal(7, scroll: 0, visible: 4, total: 10)).to eq(4)
    end

    it 'clamps to the end of the list' do
      expect(described_class.scroll_to_reveal(9, scroll: 20, visible: 4, total: 10)).to eq(6)
    end

    it 'clamps to zero for lists shorter than the window' do
      expect(described_class.scroll_to_reveal(1, scroll: 3, visible: 5, total: 2)).to eq(0)
    end
  end
end
