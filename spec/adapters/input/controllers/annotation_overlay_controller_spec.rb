# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::Controllers::AnnotationOverlayController do
  def build_deps(**overrides)
    described_class::Dependencies.build(
      reader_state: reader_state,
      reader_session_mutator: reader_session_mutator,
      annotation_overlay_ui_session: session,
      notification_service: notification_service,
      **overrides
    )
  end

  let(:reader_state) { instance_double(Shoko::Adapters::Runtime::SessionState::ReaderSnapshotProjectionAdapter, book_path: '/books/test.epub', annotations: []) }
  let(:reader_session_mutator) do
    instance_double(Shoko::Adapters::Runtime::SessionState::ReaderSessionMutator, update_reader: nil, clear_selection: nil)
  end
  let(:session) do
    instance_double(
      Shoko::Adapters::Ui::Sessions::AnnotationOverlayUiSessionAdapter,
      close_editor: nil,
      editor_context: nil,
      editor_spellcheck_target: nil,
      editor_spell_suggestions_state: nil,
      editor_show_spell_suggestions: nil
    )
  end
  let(:notification_service) { instance_double(Shoko::Adapters::Output::NotificationService, set_message: nil) }

  subject(:controller) do
    described_class.new(deps: build_deps)
  end

  it 'looks up spell suggestions for the current editor word via dictionary datasets' do
    target = { word: 'ambigues', start: 24, end: 32 }
    dictionary_service = instance_double(
      Shoko::Core::Services::DictionaryService,
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
                   Shoko::Core::Models::FuzzyMatch.new(word: 'ambiguous', similarity: 0.94),
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
      Shoko::Core::Services::DictionaryService,
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
                   Shoko::Core::Models::FuzzyMatch.new(word: 'wirtschaftlich', similarity: 0.93),
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
      Shoko::Core::Services::DictionaryService,
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
                   Shoko::Core::Models::FuzzyMatch.new(word: 'ambiguous', similarity: 0.94),
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
      Shoko::Core::Services::DictionaryService,
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
                   Shoko::Core::Models::FuzzyMatch.new(word: 'ambiguous', similarity: 0.94),
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
