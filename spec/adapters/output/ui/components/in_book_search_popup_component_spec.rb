# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Output::Ui::Components::InBookSearchPopupComponent do
  subject(:component) { described_class.new }

  let(:results) do
    [
      { chapter_index: 0, chapter_title: 'One', line_index: 2, before: 'a few', match: 'many', after: 'words here' },
      { chapter_index: 1, chapter_title: 'Two', line_index: 5, before: 'before', match: 'many', after: 'after' },
      { chapter_index: 2, chapter_title: 'Three', line_index: 7, before: 'context', match: 'many', after: 'tail' },
    ]
  end

  describe '#show and #hide' do
    it 'tracks visibility and payload' do
      component.show(query: 'many', results: results, total_matches: 3)

      expect(component).to be_visible
      expect(component.query).to eq('many')
      expect(component.results.length).to eq(3)
      expect(component.total_matches).to eq(3)

      component.hide
      expect(component).not_to be_visible
      expect(component.query).to eq('')
      expect(component.results).to eq([])
    end
  end

  describe '#handle_key' do
    before { component.show(query: '', results: [], total_matches: 0) }

    it 'emits query change for printable input and backspace' do
      expect(component.handle_key('m')).to eq(type: :query_change, query: 'm')
      expect(component.handle_key('a')).to eq(type: :query_change, query: 'ma')
      expect(component.handle_key("\x7F")).to eq(type: :query_change, query: 'm')
    end

    it 'emits close for cancel key' do
      key = Shoko::Adapters::Input::KeyDefinitions::ACTIONS[:cancel].first
      expect(component.handle_key(key)).to eq(type: :close)
    end

    it 'treats q as query input instead of closing the popup' do
      expect(component.handle_key('q')).to eq(type: :query_change, query: 'q')
      expect(component).to be_visible
    end

    it 'moves selection on navigation keys' do
      component.show(query: 'many', results: results, total_matches: 3)
      component.instance_variable_set(:@last_visible_cards, 1)
      down = Shoko::Adapters::Input::KeyDefinitions::NAVIGATION[:down].first
      up = Shoko::Adapters::Input::KeyDefinitions::NAVIGATION[:up].first

      expect(component.handle_key(down)).to eq(type: :scroll)
      expect(component.selected_index).to eq(1)
      expect(component.scroll_offset).to eq(1)

      expect(component.handle_key(up)).to eq(type: :scroll)
      expect(component.selected_index).to eq(0)
      expect(component.scroll_offset).to eq(0)
    end

    it 'submits query on enter only when query changed since last search' do
      component.handle_key('m')

      expect(component.handle_key("\n")).to eq(type: :submit_query, query: 'm')
    end

    it 'opens selected result on enter when query is already searched' do
      component.show(query: 'many', results: results, total_matches: 3)
      outcome = component.handle_key("\n")

      expect(outcome).to include(type: :open_result)
      expect(outcome[:result]).to include(chapter_index: 0, line_index: 2)
    end
  end

  describe 'overlay sizing' do
    it 'respects minimum dimensions' do
      bounds = Shoko::Adapters::Output::Ui::Components::Rect.new(x: 1, y: 1, width: 70, height: 22)
      layout = component.send(:overlay_layout, bounds)

      expect(layout.width).to be >= 62
      expect(layout.height).to be >= 16
    end
  end
end
