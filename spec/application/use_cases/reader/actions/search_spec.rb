# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::UseCases::Reader::Actions::Search do
  let(:reader_search_control) do
    instance_double('ReaderSearchControl',
                    open_search_session: :handled,
                    close_search_session: :handled,
                    submit_search_session: :handled,
                    open_search_result: :handled)
  end
  let(:reader_view_mutator) { instance_double('ReaderViewMutator', update_reader: nil) }
  let(:reader_view_state_store) { instance_double('ReaderViewStateStore', load: snapshot) }
  let(:snapshot) do
    instance_double('ReaderViewSnapshot',
                    search_query: search_query,
                    search_results: search_results,
                    search_results_query: search_results_query,
                    search_selected_index: search_selected_index)
  end
  let(:search_query) { '' }
  let(:search_results) { [] }
  let(:search_results_query) { '' }
  let(:search_selected_index) { 0 }

  subject(:use_case) do
    described_class.new(
      reader_search_control: reader_search_control,
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
    it 'opens and closes the search session via the control port' do
      expect(use_case.call(:open_in_book_search)).to eq(:handled)
      expect(reader_search_control).to have_received(:open_search_session)

      expect(use_case.call(:close_in_book_search)).to eq(:handled)
      expect(reader_search_control).to have_received(:close_search_session)
    end
  end

  describe 'editing the query' do
    let(:search_query) { 'ma' }

    it 'appends a printable character to the query state' do
      use_case.call(:edit_in_book_search, edit_op(:insert, text: 'n'))
      expect(reader_view_mutator).to have_received(:update_reader).with(search_query: 'man')
    end

    it 'ignores non-printable insert input' do
      use_case.call(:edit_in_book_search, edit_op(:insert, text: "\e"))
      expect(reader_view_mutator).not_to have_received(:update_reader)
    end

    it 'removes the last character on backspace' do
      use_case.call(:edit_in_book_search, edit_op(:backspace))
      expect(reader_view_mutator).to have_received(:update_reader).with(search_query: 'm')
    end
  end

  describe 'moving the selection' do
    let(:search_results) { [{ a: 1 }, { a: 2 }, { a: 3 }] }
    let(:search_selected_index) { 1 }

    it 'writes the next selection index' do
      use_case.call(:search_move_down, delta(1))
      expect(reader_view_mutator).to have_received(:update_reader).with(search_selected_index: 2)
    end

    it 'clamps at the bottom of the result list' do
      use_case.call(:search_move_down, delta(5))
      expect(reader_view_mutator).to have_received(:update_reader).with(search_selected_index: 2)
    end

    context 'with no results' do
      let(:search_results) { [] }

      it 'does not write a selection index' do
        use_case.call(:search_move_down, delta(1))
        expect(reader_view_mutator).not_to have_received(:update_reader)
      end
    end
  end

  describe 'confirm dispatch (three-way parity with the popup)' do
    context 'when the query changed since the last search' do
      let(:search_query) { 'foo' }
      let(:search_results_query) { 'bar' }
      let(:search_results) { [{ a: 1 }] }

      it 'submits a new search rather than opening a result' do
        use_case.call(:search_confirm)
        expect(reader_search_control).to have_received(:submit_search_session)
        expect(reader_search_control).not_to have_received(:open_search_result)
      end
    end

    context 'when the query is settled and results exist' do
      let(:search_query) { 'foo' }
      let(:search_results_query) { 'foo' }
      let(:search_results) { [{ a: 1 }, { a: 2 }] }
      let(:search_selected_index) { 1 }

      it 'opens the selected result' do
        use_case.call(:search_confirm)
        expect(reader_search_control).to have_received(:open_search_result).with({ a: 2 })
        expect(reader_search_control).not_to have_received(:submit_search_session)
      end
    end

    context 'when the query is empty with no prior search' do
      let(:search_query) { '' }
      let(:search_results_query) { '' }
      let(:search_results) { [] }

      it 'submits via the empty-query fallthrough instead of navigating' do
        use_case.call(:search_confirm)
        expect(reader_search_control).to have_received(:submit_search_session)
        expect(reader_search_control).not_to have_received(:open_search_result)
      end
    end

    context 'when a settled query returned zero results' do
      let(:search_query) { 'zzz' }
      let(:search_results_query) { 'zzz' }
      let(:search_results) { [] }

      it 're-submits via the zero-result fallthrough instead of navigating' do
        use_case.call(:search_confirm)
        expect(reader_search_control).to have_received(:submit_search_session)
        expect(reader_search_control).not_to have_received(:open_search_result)
      end
    end
  end
end
