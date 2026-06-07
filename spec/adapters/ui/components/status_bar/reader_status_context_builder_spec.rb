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

  describe 'dictionary mode' do
    def dict_result(senses: ['a forcible overthrow', 'a dramatic change'], mode: :grouped, entries: nil)
      entry = Shoko::Core::Models::DictionaryEntry.new(word: 'revolution', senses: senses)
      Shoko::Core::Models::DictionaryResult.new(
        query: 'revolution', entries: entries || [entry], source_lang: 'de', target_lang: 'en', search_mode: mode
      )
    end

    def dict_reader(**overrides)
      defaults = {
        dictionary_query: 'revolution',
        dictionary_results_query: 'revolution',
        dictionary_result: dict_result,
        dictionary_entry_index: 0,
        dictionary_fuzzy_mode: false,
        dictionary_fuzzy_matches: [],
      }
      instance_double('ReaderStateReader', **defaults.merge(overrides))
    end

    def dict_context(reader, **vm_overrides)
      vm = view_model(mode: :dictionary, **vm_overrides)
      described_class.new(-> { vm }, reader_state_reader: reader).call
    end

    it 'becomes the define input with a Dictionary badge, the query, a caret, and a sense count' do
      context = dict_context(dict_reader)

      expect(context.badge.mode).to eq('Dictionary')
      expect(context.badge.label).to eq('epub')
      expect(context.title).to eq('revolution')
      expect(context.caret).to be(true)
      expect(context.progress).to be_nil
      expect(context.trailing).to eq(['2 senses'])
    end

    it 'shows a prompt when the query is empty' do
      context = dict_context(dict_reader(dictionary_query: '', dictionary_results_query: '', dictionary_result: nil))
      expect(context.title).to eq('')
      expect(context.placeholder).not_to be_empty
      expect(context.trailing).to eq([])
    end

    it 'prompts to press enter when the query is not yet defined' do
      context = dict_context(dict_reader(dictionary_query: 'newword', dictionary_results_query: 'revolution'))
      expect(context.trailing).to eq(['↵ to define'])
    end

    it 'reports no entry for a settled empty result' do
      context = dict_context(dict_reader(dictionary_result: dict_result(entries: [])))
      expect(context.trailing).to eq(['no entry'])
    end

    it 'reports the number of similar candidates in fuzzy mode' do
      context = dict_context(dict_reader(dictionary_fuzzy_mode: true, dictionary_fuzzy_matches: %i[a b c]))
      expect(context.trailing).to eq(['3 similar'])
    end

    it 'counts entries when a lookup returns more than one' do
      multi = dict_result(entries: [
                            Shoko::Core::Models::DictionaryEntry.new(word: 'revolution', senses: ['x']),
                            Shoko::Core::Models::DictionaryEntry.new(word: 'revolutio', senses: ['y']),
                          ])
      context = dict_context(dict_reader(dictionary_result: multi))
      expect(context.trailing).to eq(['1 / 2'])
    end
  end

  describe 'translator mode' do
    def translation_result(text: 'Hallo', error: nil)
      Shoko::Core::Models::TranslationResult.new(
        query: 'hello', translated_text: text, source_lang: 'auto', target_lang: 'de', error_message: error
      )
    end

    def translator_reader(**overrides)
      defaults = {
        translator_picker_side: nil,
        translator_query: 'hello',
        translator_results_query: 'hello',
        translator_result: translation_result,
        translator_source_lang: 'auto',
        translator_target_lang: 'de',
        translator_languages: [{ code: 'en', name: 'English' }, { code: 'de', name: 'German' }],
        translator_picker_query: '',
      }
      instance_double('ReaderStateReader', **defaults.merge(overrides))
    end

    def translator_context(reader, **vm_overrides)
      vm = view_model(mode: :translator, **vm_overrides)
      described_class.new(-> { vm }, reader_state_reader: reader).call
    end

    it 'is a quiet toolbar: a Translator badge, the pair as the title, no caret' do
      context = translator_context(translator_reader)

      expect(context.badge.mode).to eq('Translator')
      expect(context.badge.label).to eq('epub')
      expect(context.title).to eq('auto → de')
      expect(context.caret).to be(false)
      expect(context.progress).to be_nil
      expect(context.trailing.first).to eq('translated')
      expect(context.trailing.last).to include('translate')
    end

    it 'reports the translate status as the leading trailing item' do
      idle = translator_context(translator_reader(translator_query: '', translator_results_query: '',
                                                  translator_result: nil))
      expect(idle.title).to eq('auto → de')
      expect(idle.trailing.first).to include('translate') # only the hint, no status

      stale = translator_context(translator_reader(translator_query: 'world', translator_results_query: 'hello'))
      expect(stale.trailing.first).to eq('↵ translate')

      failed = translator_context(translator_reader(translator_result: translation_result(error: 'boom')))
      expect(failed.trailing.first).to eq('failed')
    end

    it 'names the side being chosen and the match count while picking' do
      context = translator_context(translator_reader(translator_picker_side: :target, translator_picker_query: 'ger'))

      expect(context.badge.mode).to eq('Translator')
      expect(context.title).to eq('Languages · Target')
      expect(context.caret).to be(false)
      expect(context.trailing.first).to eq('1 match')
    end
  end
end
