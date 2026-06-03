# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::Controllers::InBookSearchController do
  def success_outcome(payload: nil, code: :ok, status: :handled)
    Shoko::Shared::Contracts::SessionOutcome.success(status: status, code: code, payload: payload)
  end

  let(:in_book_search_ui_session) do
    instance_double('InBookSearchUiSession',
                    open: success_outcome(code: :in_book_search_opened, status: :opened),
                    close: success_outcome(code: :in_book_search_closed, status: :closed),
                    apply_results: success_outcome(code: :in_book_search_results_applied),
                    visible?: true)
  end
  let(:reader_session_mutator) { instance_double('ReaderSessionMutator', update_reader: nil) }
  let(:input_controller) { instance_double('InputController', enter_modal_mode: nil, exit_modal_mode: nil) }
  let(:state_controller) { instance_double('StateController', jump_to_chapter_offset: nil) }
  let(:page_calculator) { instance_double('PageCalculator', pages_data: [], get_page: nil) }
  let(:reader_controller) { instance_double('ReaderController', draw_screen: nil, page_calculator: page_calculator) }
  let(:search_result) do
    instance_double('SearchResult', query: 'many', matches: [{ match: 'many' }], total_matches: 1)
  end
  let(:search_service) { instance_double('SearchService', search: search_result) }
  let(:reader_state) do
    instance_double('ReaderState', in_book_search_popup: nil, mode: :read, current_page_index: 17, search_query: 'many')
  end
  let(:notification_service) { instance_double('NotificationService', set_message: nil) }
  let(:clock) { instance_double('Clock', monotonic_now: 100.0) }

  subject(:controller) do
    described_class.new(
      reader_state: reader_state,
      reader_session_mutator: reader_session_mutator,
      search_service: search_service,
      input_controller: input_controller,
      reader_controller: reader_controller,
      state_controller: state_controller,
      notification_service: notification_service,
      logger: nil,
      in_book_search_ui_session: in_book_search_ui_session,
      clock: clock
    )
  end

  describe '#open_in_book_search' do
    it 'opens the session, clears the landing highlight, and activates modal mode' do
      expect(controller.open_in_book_search).to eq(:handled)

      expect(reader_session_mutator).to have_received(:update_reader).with(search_landing_highlight: nil)
      expect(in_book_search_ui_session).to have_received(:open)
      expect(input_controller).to have_received(:enter_modal_mode).with(:in_book_search)
    end
  end

  describe '#submit_in_book_search' do
    it 'runs the search service with the state query and publishes the results' do
      expect(controller.submit_in_book_search).to eq(:handled)

      expect(search_service).to have_received(:search).with('many')
      expect(in_book_search_ui_session).to have_received(:apply_results).with(
        query: 'many',
        results: [{ match: 'many' }],
        total_matches: 1
      )
    end
  end

  describe '#open_search_result' do
    it 'jumps to the selected result and closes the popup' do
      result = {
        chapter_index: 2,
        line_index: 3,
        chapter_title: 'Third',
        before: 'The political and ',
        match: 'economic',
        after: ' order shifted',
      }
      pages = [
        { chapter_index: 2, start_line: 10, lines: ['The political', 'and economic', 'order shifted'] },
      ]
      allow(page_calculator).to receive(:pages_data).and_return(pages)
      allow(page_calculator).to receive(:get_page).with(0).and_return(pages.first)

      expect(controller.open_search_result(result)).to eq(:handled)
      expect(state_controller).to have_received(:jump_to_chapter_offset).with(2, 11)
      expect(reader_session_mutator).to have_received(:update_reader).with(
        search_landing_highlight: {
          chapter_index: 2,
          line_index: 11,
          page_index: 17,
          started_at: 100.0,
          expires_at: 101.4,
          query: 'economic',
          before: 'The political and ',
          match_text: 'economic',
          after: ' order shifted',
        }
      )
      expect(in_book_search_ui_session).to have_received(:close)
    end

    it 'builds the landing highlight from a SearchMatch struct, not just a hash' do
      result = Shoko::Core::Services::InBookSearchService::SearchMatch.new(
        2, 'Third', 3, 'The political and ', 'economic', ' order shifted', nil, nil
      )

      expect(controller.open_search_result(result)).to eq(:handled)
      expect(reader_session_mutator).to have_received(:update_reader).with(
        hash_including(search_landing_highlight: hash_including(match_text: 'economic', query: 'economic'))
      )
    end

    it 'trusts exact wrapped result offsets instead of re-matching ambiguous snippets' do
      result = {
        chapter_index: 2,
        line_index: 22,
        page_index: 1,
        line_space: 'wrapped',
        chapter_title: 'Third',
        before: 'alpha ',
        match: 'target',
        after: ' beta',
      }
      pages = [
        { chapter_index: 2, start_line: 20, end_line: 21, lines: ['alpha target beta', 'filler'] },
        { chapter_index: 2, start_line: 22, end_line: 23, lines: ['alpha target beta', 'selected occurrence'] },
      ]
      allow(page_calculator).to receive(:pages_data).and_return(pages)
      allow(page_calculator).to receive(:get_page).with(1).and_return(pages[1])

      expect(controller.open_search_result(result)).to eq(:handled)
      expect(state_controller).to have_received(:jump_to_chapter_offset).with(2, 22)
    end
  end

  describe '#close_in_book_search' do
    it 'closes the session and exits modal mode' do
      allow(reader_state).to receive(:mode).and_return(:in_book_search)

      expect(controller.close_in_book_search).to eq(:handled)
      expect(in_book_search_ui_session).to have_received(:close)
      expect(input_controller).to have_received(:exit_modal_mode).with(:in_book_search)
    end
  end
end
