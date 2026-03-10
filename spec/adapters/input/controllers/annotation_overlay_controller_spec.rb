# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::Controllers::AnnotationOverlayController do
  def build_deps(**overrides)
    described_class::Dependencies.build(
      **{
        reader_state: reader_state,
        reader_session_mutator: reader_session_mutator,
        annotation_overlay_ui_session: session,
        notification_service: notification_service
      }.merge(overrides)
    )
  end

  let(:reader_state) { instance_double('ReaderStateReader', book_path: '/books/test.epub', annotations: []) }
  let(:reader_session_mutator) do
    instance_double('ReaderSessionMutator', update_reader: nil, clear_selection: nil, update_sidebar: nil)
  end
  let(:session) do
    instance_double(
      'AnnotationOverlayUiSession',
      close_editor: nil,
      editor_context: nil,
      editor_spellcheck_target: nil,
      editor_spell_suggestions_state: nil,
      editor_show_spell_suggestions: nil
    )
  end
  let(:notification_service) { instance_double('NotificationService', set_message: nil) }

  subject(:controller) do
    described_class.new(deps: build_deps)
  end

  it 'ignores non-hash editor payloads from session outcomes' do
    allow(session).to receive(:editor_insert_char).with('a').and_return(
      Shoko::Shared::Contracts::SessionOutcome.success(
        status: :handled,
        code: :editor_insert_char_handled,
        payload: 1.2345
      )
    )

    expect { controller.annotation_editor_insert_char('a') }.not_to raise_error
    expect(controller.annotation_editor_insert_char('a')).to eq(:handled)
  end

  it 'saves annotation when editor session returns a save event payload' do
    annotation_service = instance_double('AnnotationService', add: nil)
    allow(session).to receive(:editor_save).and_return(
      Shoko::Shared::Contracts::SessionOutcome.success(
        status: :handled,
        code: :annotation_editor_save_handled,
        payload: { type: :save, note: 'my note' }
      )
    )
    allow(session).to receive(:editor_context).and_return(
      annotation_id: nil,
      selected_text: 'selected text',
      note: 'my note',
      selection_range: { start: 3, end: 9 },
      chapter_index: 2
    )

    controller_with_service = described_class.new(deps: build_deps(annotation_service: annotation_service))

    controller_with_service.annotation_editor_save

    expect(annotation_service).to have_received(:add).with(
      '/books/test.epub',
      'selected text',
      'my note',
      { start: 3, end: 9 },
      2,
      nil
    )
    expect(session).to have_received(:close_editor)
    expect(reader_session_mutator).to have_received(:clear_selection)
  end

  it 'looks up spell suggestions for the current editor word via dictionary datasets' do
    target = { word: 'ambigues', start: 24, end: 32 }
    dictionary_service = instance_double(
      'DictionaryService',
      available?: true,
      available_language_pairs: [{ source: 'en', target: 'de' }],
      configured_source_lang: 'de',
      configured_target_lang: 'en'
    )
    allow(session).to receive(:editor_spellcheck_target).and_return(
      Shoko::Shared::Contracts::SessionOutcome.success(
        status: :handled,
        code: :annotation_editor_spellcheck_target_handled,
        payload: target
      )
    )
    allow(session).to receive(:editor_show_spell_suggestions).with(
      target: target,
      suggestions: ['ambiguous'],
      scope_key: 'lang:en',
      scope_label: 'English',
      can_cycle: true
    ).and_return(
      Shoko::Shared::Contracts::SessionOutcome.success(
        status: :handled,
        code: :annotation_editor_spell_suggestions_shown
      )
    )
    allow(dictionary_service).to receive(:fuzzy_search).and_return([])
    allow(dictionary_service).to receive(:fuzzy_search_translations).and_return([])
    allow(dictionary_service).to receive(:fuzzy_search).with(
      'ambigues',
      source_lang: 'en',
      target_lang: 'de',
      limit: 15
    ).and_return([
                    Shoko::Core::Models::FuzzyMatch.new(word: 'ambiguous', similarity: 0.94)
                  ])

    controller_with_dictionary = described_class.new(deps: build_deps(dictionary_service: dictionary_service))

    expect(controller_with_dictionary.annotation_editor_spellcheck).to eq(:handled)
    expect(session).to have_received(:editor_show_spell_suggestions).with(
      target: target,
      suggestions: ['ambiguous'],
      scope_key: 'lang:en',
      scope_label: 'English',
      can_cycle: true
    )
  end

  it 'falls back to translation-side matches so German suggestions still work from an en-de dataset' do
    target = { word: 'wirtschaffdlich', start: 12, end: 27 }
    dictionary_service = instance_double(
      'DictionaryService',
      available?: true,
      available_language_pairs: [{ source: 'en', target: 'de' }],
      configured_source_lang: 'de',
      configured_target_lang: 'en'
    )
    allow(session).to receive(:editor_spellcheck_target).and_return(
      Shoko::Shared::Contracts::SessionOutcome.success(
        status: :handled,
        code: :annotation_editor_spellcheck_target_handled,
        payload: target
      )
    )
    allow(session).to receive(:editor_show_spell_suggestions).with(
      target: target,
      suggestions: ['wirtschaftlich'],
      scope_key: 'lang:de',
      scope_label: 'German',
      can_cycle: true
    ).and_return(
      Shoko::Shared::Contracts::SessionOutcome.success(
        status: :handled,
        code: :annotation_editor_spell_suggestions_shown
      )
    )
    allow(dictionary_service).to receive(:fuzzy_search).and_return([])
    allow(dictionary_service).to receive(:fuzzy_search_translations).and_return([])
    allow(dictionary_service).to receive(:fuzzy_search_translations).with(
      'wirtschaffdlich',
      source_lang: 'en',
      target_lang: 'de',
      limit: 15
    ).and_return([
                    Shoko::Core::Models::FuzzyMatch.new(word: 'wirtschaftlich', similarity: 0.93)
                  ])

    controller_with_dictionary = described_class.new(deps: build_deps(dictionary_service: dictionary_service))

    expect(controller_with_dictionary.annotation_editor_spellcheck).to eq(:handled)
    expect(session).to have_received(:editor_show_spell_suggestions).with(
      target: target,
      suggestions: ['wirtschaftlich'],
      scope_key: 'lang:de',
      scope_label: 'German',
      can_cycle: true
    )
  end

  it 'cycles to the next spell lookup scope when alt+d is pressed again on the same word' do
    target = { word: 'ambigues', start: 24, end: 32 }
    dictionary_service = instance_double(
      'DictionaryService',
      available?: true,
      available_language_pairs: [{ source: 'en', target: 'de' }, { source: 'de', target: 'en' }],
      configured_source_lang: 'de',
      configured_target_lang: 'en'
    )
    allow(session).to receive(:editor_spellcheck_target).and_return(
      Shoko::Shared::Contracts::SessionOutcome.success(
        status: :handled,
        code: :annotation_editor_spellcheck_target_handled,
        payload: target
      )
    )
    allow(session).to receive(:editor_spell_suggestions_state).and_return(
      nil,
      Shoko::Shared::Contracts::SessionOutcome.success(
        status: :handled,
        code: :annotation_editor_spell_suggestions_state_handled,
        payload: { word: 'ambigues', start: 24, end: 32, scope_key: 'lang:en' }
      )
    )
    allow(session).to receive(:editor_show_spell_suggestions).with(
      target: target,
      suggestions: ['ambiguous'],
      scope_key: 'lang:en',
      scope_label: 'English',
      can_cycle: true
    ).and_return(
      Shoko::Shared::Contracts::SessionOutcome.success(status: :handled, code: :annotation_editor_spell_suggestions_shown)
    )
    allow(session).to receive(:editor_show_spell_suggestions).with(
      target: target,
      suggestions: [],
      scope_key: 'lang:de',
      scope_label: 'German',
      can_cycle: true
    ).and_return(
      Shoko::Shared::Contracts::SessionOutcome.success(status: :handled, code: :annotation_editor_spell_suggestions_shown)
    )
    allow(dictionary_service).to receive(:fuzzy_search).and_return([])
    allow(dictionary_service).to receive(:fuzzy_search_translations).and_return([])
    allow(dictionary_service).to receive(:fuzzy_search).with(
      'ambigues',
      source_lang: 'en',
      target_lang: 'de',
      limit: 15
    ).and_return([
                    Shoko::Core::Models::FuzzyMatch.new(word: 'ambiguous', similarity: 0.94)
                  ])

    controller_with_dictionary = described_class.new(deps: build_deps(dictionary_service: dictionary_service))

    expect(controller_with_dictionary.annotation_editor_spellcheck).to eq(:handled)
    expect(controller_with_dictionary.annotation_editor_spellcheck).to eq(:handled)
    expect(session).to have_received(:editor_show_spell_suggestions).with(
      target: target,
      suggestions: [],
      scope_key: 'lang:de',
      scope_label: 'German',
      can_cycle: true
    )
  end

  it 'resets to the best matching scope when the word changed at the same range' do
    target = { word: 'ambigues', start: 24, end: 32 }
    dictionary_service = instance_double(
      'DictionaryService',
      available?: true,
      available_language_pairs: [{ source: 'en', target: 'de' }, { source: 'de', target: 'en' }],
      configured_source_lang: 'de',
      configured_target_lang: 'en'
    )
    allow(session).to receive(:editor_spellcheck_target).and_return(
      Shoko::Shared::Contracts::SessionOutcome.success(
        status: :handled,
        code: :annotation_editor_spellcheck_target_handled,
        payload: target
      )
    )
    allow(session).to receive(:editor_spell_suggestions_state).and_return(
      Shoko::Shared::Contracts::SessionOutcome.success(
        status: :handled,
        code: :annotation_editor_spell_suggestions_state_handled,
        payload: { word: 'wirtschaffdlich', start: 24, end: 32, scope_key: 'lang:de' }
      )
    )
    allow(session).to receive(:editor_show_spell_suggestions).with(
      target: target,
      suggestions: ['ambiguous'],
      scope_key: 'lang:en',
      scope_label: 'English',
      can_cycle: true
    ).and_return(
      Shoko::Shared::Contracts::SessionOutcome.success(status: :handled, code: :annotation_editor_spell_suggestions_shown)
    )
    allow(dictionary_service).to receive(:fuzzy_search).and_return([])
    allow(dictionary_service).to receive(:fuzzy_search_translations).and_return([])
    allow(dictionary_service).to receive(:fuzzy_search).with(
      'ambigues',
      source_lang: 'en',
      target_lang: 'de',
      limit: 15
    ).and_return([
                    Shoko::Core::Models::FuzzyMatch.new(word: 'ambiguous', similarity: 0.94)
                  ])

    controller_with_dictionary = described_class.new(deps: build_deps(dictionary_service: dictionary_service))

    expect(controller_with_dictionary.annotation_editor_spellcheck).to eq(:handled)
    expect(session).to have_received(:editor_show_spell_suggestions).with(
      target: target,
      suggestions: ['ambiguous'],
      scope_key: 'lang:en',
      scope_label: 'English',
      can_cycle: true
    )
  end
end
