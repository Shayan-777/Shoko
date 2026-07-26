# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Ui::Components::Screens::RssLookupScreenComponent do
  include MenuScreenRenderHelpers

  let(:menu_state_reader) do
    instance_double(
      Shoko::Adapters::Runtime::SessionState::MenuSnapshotProjectionAdapter,
      rss_lookup_query: 'Haus',
      rss_lookup_status: :ready,
      rss_lookup_message: '',
      rss_content_scroll: 0,
      rss_lookup_result: {
        query: 'Haus',
        entries: [
          { word: 'Haus', senses: ['a building for living in'], translations: %w[house home] },
        ],
      }
    )
  end
  let(:component) { described_class.new(menu_state_reader: menu_state_reader) }

  def text_for(width: 70, height: 20)
    rendered_text(render_component(component, width: width, height: height))
  end

  it 'names the view and the word looked up' do
    expect(text_for).to include('Dictionary').and include('Haus')
  end

  it 'numbers the senses' do
    expect(text_for).to include('1. a building for living in')
  end

  it 'lists the translations together' do
    expect(text_for).to include('house, home')
  end

  it 'separates several entries' do
    allow(menu_state_reader).to receive(:rss_lookup_result).and_return(
      { query: 'Bank', entries: [{ word: 'Bank', senses: ['seat'], translations: ['bench'] },
                                 { word: 'Bank', senses: ['for money'], translations: ['bank'] }] }
    )

    expect(text_for).to include('1. seat').and include('1. for money')
  end

  it 'reads a payload that has been through the state tree with string keys' do
    allow(menu_state_reader).to receive(:rss_lookup_result).and_return(
      { 'query' => 'Haus', 'entries' => [{ 'word' => 'Haus', 'senses' => ['a building'], 'translations' => [] }] }
    )

    expect(text_for).to include('1. a building')
  end

  it 'says it is working while the lookup runs' do
    allow(menu_state_reader).to receive_messages(rss_lookup_status: :loading, rss_lookup_result: nil,
                                                 rss_lookup_message: '')

    expect(text_for).to include('Looking up')
  end

  it 'says so when the word is not in the dictionary' do
    allow(menu_state_reader).to receive_messages(rss_lookup_status: :empty, rss_lookup_result: nil,
                                                 rss_lookup_message: '')

    expect(text_for).to include('No entry for')
  end

  it 'shows a backend failure message rather than an empty pane' do
    allow(menu_state_reader).to receive_messages(rss_lookup_status: :error, rss_lookup_result: nil,
                                                 rss_lookup_message: 'Dictionary database is corrupted.')

    expect(text_for).to include('Dictionary database is corrupted.')
  end

  it 'tells the reader how to get back to the article' do
    expect(text_for).to include('back to the article')
  end

  it 'wraps a long sense to the measure' do
    allow(menu_state_reader).to receive(:rss_lookup_result).and_return(
      { query: 'x', entries: [{ word: 'x', senses: [(['wort'] * 40).join(' ')], translations: [] }] }
    )

    rendered_grid(render_component(component, width: 50, height: 20), width: 50, height: 20).each do |row|
      expect(row.length).to be <= 50
    end
  end
end
