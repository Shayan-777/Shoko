# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::UseCases::Reader::Actions::Dictionary do
  let(:reader_dictionary_control) do
    instance_double('ReaderDictionaryControl',
                    open_dictionary_lookup: :handled,
                    close_dictionary_lookup: :handled,
                    submit_dictionary_lookup: :handled,
                    cycle_dictionary_result: :handled,
                    cycle_dictionary_pair: :handled,
                    swap_dictionary_languages: :handled,
                    toggle_dictionary_fuzzy_matching: :handled,
                    edit_dictionary_setup: :handled,
                    confirm_dictionary_setup: :handled,
                    move_dictionary_setup: :handled,
                    apply_dictionary_setup: :handled)
  end
  let(:reader_view_mutator) { instance_double('ReaderViewMutator', update_reader: nil) }
  let(:reader_view_state_store) { instance_double('ReaderViewStateStore', load: snapshot) }
  let(:snapshot) do
    instance_double('ReaderViewSnapshot',
                    dictionary_query: dictionary_query,
                    dictionary_results_query: dictionary_results_query,
                    dictionary_selected_index: dictionary_selected_index,
                    dictionary_fuzzy_mode: dictionary_fuzzy_mode,
                    dictionary_fuzzy_matches: dictionary_fuzzy_matches,
                    dictionary_setup_active: dictionary_setup_active)
  end
  let(:dictionary_query) { '' }
  let(:dictionary_results_query) { '' }
  let(:dictionary_selected_index) { 0 }
  let(:dictionary_fuzzy_mode) { false }
  let(:dictionary_fuzzy_matches) { [] }
  let(:dictionary_setup_active) { false }

  subject(:use_case) do
    described_class.new(
      reader_dictionary_control: reader_dictionary_control,
      reader_view_state_store: reader_view_state_store,
      reader_view_mutator: reader_view_mutator
    )
  end

  def edit_op(operation, text: nil)
    Shoko::Application::UseCases::Requests::EditOp.new(operation: operation, text: text)
  end

  def delta(value)
    Shoko::Application::UseCases::Requests::SelectionDelta.new(delta: value)
  end

  describe 'lifecycle intents' do
    it 'opens the lookup with the raw payload and closes via the control port' do
      payload = { data: { selection_range: {} } }
      expect(use_case.call(:open_dictionary, payload)).to eq(:handled)
      expect(reader_dictionary_control).to have_received(:open_dictionary_lookup).with(payload)

      expect(use_case.call(:close_dictionary)).to eq(:handled)
      expect(reader_dictionary_control).to have_received(:close_dictionary_lookup)
    end

    it 'opens with a nil payload (hotkey)' do
      use_case.call(:open_dictionary, nil)
      expect(reader_dictionary_control).to have_received(:open_dictionary_lookup).with(nil)
    end
  end

  describe 'editing the query (lookup)' do
    let(:dictionary_query) { 're' }

    it 'appends a printable character to the query state' do
      use_case.call(:edit_reader_dictionary_query, edit_op(:insert, text: 'v'))
      expect(reader_view_mutator).to have_received(:update_reader).with(dictionary_query: 'rev')
    end

    it 'removes the last character on backspace' do
      use_case.call(:edit_reader_dictionary_query, edit_op(:backspace))
      expect(reader_view_mutator).to have_received(:update_reader).with(dictionary_query: 'r')
    end

    it 'ignores non-printable insert input' do
      use_case.call(:edit_reader_dictionary_query, edit_op(:insert, text: "\e"))
      expect(reader_view_mutator).not_to have_received(:update_reader)
    end
  end

  describe 'scrolling/selecting (lookup)' do
    let(:dictionary_selected_index) { 1 }

    it 'increments the scroll offset for the definition card' do
      use_case.call(:dictionary_move_down, delta(1))
      expect(reader_view_mutator).to have_received(:update_reader).with(dictionary_selected_index: 2)
    end

    it 'never scrolls above the top' do
      use_case.call(:dictionary_move_up, delta(-5))
      expect(reader_view_mutator).to have_received(:update_reader).with(dictionary_selected_index: 0)
    end

    context 'in fuzzy mode' do
      let(:dictionary_fuzzy_mode) { true }
      let(:dictionary_fuzzy_matches) { [double, double, double] }

      it 'clamps the candidate index to the list' do
        use_case.call(:dictionary_move_down, delta(5))
        expect(reader_view_mutator).to have_received(:update_reader).with(dictionary_selected_index: 2)
      end
    end
  end

  describe 'confirm dispatch' do
    context 'when the query changed since the last lookup' do
      let(:dictionary_query) { 'rev' }
      let(:dictionary_results_query) { 'old' }

      it 'submits a new lookup' do
        use_case.call(:dictionary_confirm)
        expect(reader_dictionary_control).to have_received(:submit_dictionary_lookup)
      end
    end

    context 'when a fuzzy candidate is selected on a settled query' do
      let(:dictionary_query) { 'rev' }
      let(:dictionary_results_query) { 'rev' }
      let(:dictionary_fuzzy_mode) { true }
      let(:dictionary_selected_index) { 1 }
      let(:dictionary_fuzzy_matches) do
        [Shoko::Core::Models::FuzzyMatch.new(word: 'revolt', similarity: 0.9),
         Shoko::Core::Models::FuzzyMatch.new(word: 'revolution', similarity: 0.8)]
      end

      it 'defines the selected candidate' do
        use_case.call(:dictionary_confirm)
        expect(reader_view_mutator).to have_received(:update_reader).with(dictionary_query: 'revolution')
        expect(reader_dictionary_control).to have_received(:submit_dictionary_lookup)
      end
    end

    context 'when the query is settled and not fuzzy' do
      let(:dictionary_query) { 'rev' }
      let(:dictionary_results_query) { 'rev' }

      it 'is a no-op' do
        use_case.call(:dictionary_confirm)
        expect(reader_dictionary_control).not_to have_received(:submit_dictionary_lookup)
      end
    end
  end

  describe 'setup routing (install wizard active)' do
    let(:dictionary_setup_active) { true }

    it 'routes edits, confirm, move and tab to the wizard instead of the query' do
      use_case.call(:edit_reader_dictionary_query, edit_op(:insert, text: 'e'))
      expect(reader_dictionary_control).to have_received(:edit_dictionary_setup)
      expect(reader_view_mutator).not_to have_received(:update_reader)

      use_case.call(:dictionary_confirm)
      expect(reader_dictionary_control).to have_received(:confirm_dictionary_setup)

      use_case.call(:dictionary_move_down, delta(1))
      expect(reader_dictionary_control).to have_received(:move_dictionary_setup).with(delta: 1)

      use_case.call(:dictionary_cycle_result)
      expect(reader_dictionary_control).to have_received(:apply_dictionary_setup)
    end
  end

  describe 'service-coordinated commands' do
    it 'delegates cycle/pair/swap/fuzzy to the control port' do
      use_case.call(:dictionary_cycle_result)
      expect(reader_dictionary_control).to have_received(:cycle_dictionary_result)

      use_case.call(:dictionary_cycle_pair)
      expect(reader_dictionary_control).to have_received(:cycle_dictionary_pair)

      use_case.call(:dictionary_swap_languages)
      expect(reader_dictionary_control).to have_received(:swap_dictionary_languages)

      use_case.call(:dictionary_toggle_fuzzy)
      expect(reader_dictionary_control).to have_received(:toggle_dictionary_fuzzy_matching)
    end
  end
end
