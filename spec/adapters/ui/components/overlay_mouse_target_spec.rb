# frozen_string_literal: true

require 'spec_helper'
require 'shoko/adapters/ui/components/overlay_mouse_target'

RSpec.describe Shoko::Adapters::Ui::Components::OverlayMouseTarget do
  let(:host_class) do
    Class.new do
      include Shoko::Adapters::Ui::Components::OverlayMouseTarget
    end
  end
  let(:host) { host_class.new }

  describe '#hit_test with single-row items' do
    before do
      # A 5-item list, 3 visible, scrolled by 1, top rule on row 10, cols 1..20.
      host.record_overlay_geometry(rule_row: 10, col: 1, width: 20, visible: 3, rows_per: 1, scroll: 1, count: 5)
    end

    it 'maps each visible row to its absolute item index' do
      expect(host.hit_test(5, 11)).to eq(1) # first item row -> scroll + 0
      expect(host.hit_test(5, 12)).to eq(2)
      expect(host.hit_test(5, 13)).to eq(3) # last visible -> scroll + 2
    end

    it 'treats the top rule and rows past the visible window as inert' do
      expect(host.hit_test(5, 10)).to eq(:inside) # the rule itself
      expect(host.hit_test(5, 14)).to eq(:inside) # below the last visible slot
    end

    it 'treats clicks above the panel as a dismiss gesture' do
      expect(host.hit_test(5, 9)).to eq(:outside)
      expect(host.hit_test(5, 1)).to eq(:outside)
    end

    it 'ignores clicks outside the panel columns' do
      expect(host.hit_test(0, 11)).to eq(:inside)
      expect(host.hit_test(21, 11)).to eq(:inside)
    end
  end

  describe '#hit_test with multi-row blocks' do
    before do
      # Search/notes blocks are 3 rows each: 2 visible blocks from row 8.
      host.record_overlay_geometry(rule_row: 7, col: 1, width: 30, visible: 2, rows_per: 3, scroll: 0, count: 4)
    end

    it 'maps every row of a block to the same item' do
      expect(host.hit_test(5, 8)).to eq(0)
      expect(host.hit_test(5, 9)).to eq(0)
      expect(host.hit_test(5, 10)).to eq(0)
      expect(host.hit_test(5, 11)).to eq(1)
      expect(host.hit_test(5, 13)).to eq(1)
    end
  end

  describe '#hit_test for a non-list face' do
    before do
      host.record_overlay_geometry(rule_row: 12, col: 1, width: 24, visible: 0, rows_per: 1, scroll: 0, count: 0)
    end

    it 'is inert on the card but still dismisses from above' do
      expect(host.hit_test(5, 13)).to eq(:inside)
      expect(host.hit_test(5, 12)).to eq(:inside)
      expect(host.hit_test(5, 11)).to eq(:outside)
    end
  end

  describe 'when nothing was recorded' do
    it 'returns :inside (no geometry, no action)' do
      expect(host.hit_test(5, 5)).to eq(:inside)
    end

    it 'returns :inside again after clearing' do
      host.record_overlay_geometry(rule_row: 5, col: 1, width: 10, visible: 1, rows_per: 1, scroll: 0, count: 1)
      host.clear_overlay_geometry
      expect(host.hit_test(5, 6)).to eq(:inside)
    end

    it 'clamps a stale higher index to inert when the count shrinks' do
      host.record_overlay_geometry(rule_row: 10, col: 1, width: 20, visible: 3, rows_per: 1, scroll: 0, count: 1)
      expect(host.hit_test(5, 12)).to eq(:inside) # slot 1 -> index 1, but count is 1
    end
  end
end
