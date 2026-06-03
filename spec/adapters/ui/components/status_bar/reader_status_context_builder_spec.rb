# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Ui::Components::StatusBar::ReaderStatusContextBuilder do
  def view_model(**overrides)
    Shoko::Adapters::Ui::ViewModels::ReaderViewModel.new(
      document_title: 'The Great Gatsby',
      source_format: :epub,
      current_chapter: 2,
      total_chapters: 12,
      chapter_title: 'The Valley of Ashes',
      page_info: { current: 42, total: 318 },
      mode: :read,
      **overrides
    )
  end

  def build(view_model)
    described_class.new(-> { view_model }).call
  end

  it 'builds a full reader context with badge, chapter, page count and progress' do
    context = build(view_model)

    expect(context.badge.mode).to eq('Reader')
    expect(context.badge.label).to eq('epub')
    expect(context.title).to eq('The Great Gatsby')
    expect(context.details).to eq(['Ch 3/12', 'The Valley of Ashes'])
    expect(context.trailing).to eq(['42 / 318'])
    expect(context.progress).to be_within(0.0001).of(42.0 / 318)
    expect(context.progress_rgb).to eq([63, 185, 80])
  end

  it 'omits the chapter detail when the book has a single chapter' do
    expect(build(view_model(total_chapters: 1)).details).to eq([])
  end

  it 'uses the left page when split-view page info is present' do
    info = { left: { current: 10, total: 200 }, right: { current: 11, total: 200 } }
    context = build(view_model(page_info: info))

    expect(context.trailing).to eq(['10 / 200'])
    expect(context.progress).to be_within(0.0001).of(10.0 / 200)
  end

  it 'is hidden in help mode' do
    expect(build(view_model(mode: :help))).to be_nil
  end

  it 'is hidden when no view model is available' do
    expect(described_class.new(-> {}).call).to be_nil
  end

  describe 'in-book search mode' do
    def search_reader(**overrides)
      defaults = {
        search_query: 'whale',
        search_results: [{ match: 'whale' }, { match: 'whale' }],
        search_results_query: 'whale',
        search_selected_index: 0,
      }
      instance_double('ReaderStateReader', **defaults.merge(overrides))
    end

    def search_context(reader, **vm_overrides)
      vm = view_model(mode: :in_book_search, **vm_overrides)
      described_class.new(-> { vm }, reader_state_reader: reader).call
    end

    it 'becomes the search input with a Search badge, the query, and a caret' do
      context = search_context(search_reader)

      expect(context.badge.mode).to eq('Search')
      expect(context.badge.label).to eq('epub')
      expect(context.title).to eq('whale')
      expect(context.caret).to be(true)
      expect(context.progress).to be_nil
      expect(context.trailing).to eq(['1 / 2'])
    end

    it 'shows a prompt when the query is empty' do
      context = search_context(search_reader(search_query: '', search_results: [], search_results_query: ''))
      expect(context.title).to eq('')
      expect(context.placeholder).not_to be_empty
      expect(context.trailing).to eq([])
    end

    it 'prompts to press enter when the query is not yet searched' do
      context = search_context(search_reader(search_query: 'newterm', search_results_query: 'whale'))
      expect(context.trailing).to eq(['↵ to search'])
    end

    it 'reports no matches for a settled empty result set' do
      context = search_context(search_reader(search_results: [], search_results_query: 'whale'))
      expect(context.trailing).to eq(['no matches'])
    end
  end
end
