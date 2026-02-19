# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Controllers::InBookSearchController do
  def success_outcome(payload: nil, code: :ok, status: :handled)
    Shoko::Application::UI::SessionOutcome.success(status: status, code: code, payload: payload)
  end

  let(:popup) do
    instance_double(
      'InBookSearchPopup',
      show: nil,
      update: nil,
      hide: nil,
      handle_key: nil,
      visible?: true
    )
  end
  let(:in_book_search_ui_session) do
    instance_double('InBookSearchUiSession',
                    open: success_outcome(code: :in_book_search_opened, status: :opened),
                    close: success_outcome(code: :in_book_search_closed, status: :closed),
                    visible?: true,
                    insert_char: success_outcome(payload: nil, code: :in_book_search_insert_char_handled),
                    backspace: success_outcome(payload: nil, code: :in_book_search_backspace_handled),
                    confirm: success_outcome(payload: nil, code: :in_book_search_confirm_handled),
                    cancel: success_outcome(payload: nil, code: :in_book_search_cancel_handled),
                    scroll_up: success_outcome(payload: true, code: :in_book_search_scroll_up_handled),
                    scroll_down: success_outcome(payload: true, code: :in_book_search_scroll_down_handled),
                    update: success_outcome(payload: true, code: :in_book_search_update_handled))
  end
  let(:state_writer) { instance_double('StateWriter', update_reader: nil) }
  let(:input_controller) { instance_double('InputController', enter_modal_mode: nil, exit_modal_mode: nil) }
  let(:state_controller) { instance_double('StateController', jump_to_chapter_offset: nil) }
  let(:reader_controller) { instance_double('ReaderController', draw_screen: nil) }
  let(:search_result) do
    instance_double('SearchResult', query: 'many', matches: [{ match: 'many' }], total_matches: 1)
  end
  let(:search_service) { instance_double('SearchService', search: search_result) }
  let(:reader_state) { instance_double('ReaderState', in_book_search_popup: popup, mode: :read) }

  subject(:controller) do
    described_class.new(
      reader_state: reader_state,
      state_writer: state_writer,
      search_service: search_service,
      input_controller: input_controller,
      reader_controller: reader_controller,
      state_controller: state_controller,
      notification_service: nil,
      logger: nil,
      in_book_search_ui_session: in_book_search_ui_session
    )
  end

  describe '#open_in_book_search' do
    it 'shows popup, updates state, and activates modal mode' do
      expect(controller.open_in_book_search).to eq(:handled)

      expect(in_book_search_ui_session).to have_received(:open).with(query: '', results: [], total_matches: 0)
      expect(input_controller).to have_received(:enter_modal_mode).with(:in_book_search)
    end
  end

  describe 'input intents' do
    it 'does not run search while typing' do
      allow(popup).to receive(:handle_key).with('m').and_return(type: :query_change, query: 'many')
      allow(in_book_search_ui_session).to receive(:insert_char).with('m')
                                                            .and_return(success_outcome(payload: { type: :query_change, query: 'many' }))

      expect(controller.in_book_search_insert_char('m')).to eq(:handled)
      expect(search_service).not_to have_received(:search)
      expect(in_book_search_ui_session).not_to have_received(:update)
    end

    it 'runs search on submit_query' do
      allow(in_book_search_ui_session).to receive(:confirm)
        .and_return(success_outcome(payload: { type: :submit_query, query: 'many' }))

      expect(controller.in_book_search_confirm).to eq(:handled)
      expect(search_service).to have_received(:search).with('many')
      expect(in_book_search_ui_session).to have_received(:update).with(
        query: 'many',
        results: [{ match: 'many' }],
        total_matches: 1,
        results_query: 'many'
      )
    end

    it 'closes popup on close event' do
      allow(in_book_search_ui_session).to receive(:cancel)
        .and_return(success_outcome(payload: { type: :close }))

      expect(controller.in_book_search_cancel).to eq(:handled)
      expect(in_book_search_ui_session).to have_received(:close)
      expect(input_controller).to have_received(:exit_modal_mode).with(:in_book_search)
    end

    it 'jumps to selected result and closes popup on open_result' do
      result = { chapter_index: 2, line_index: 11, chapter_title: 'Third' }
      allow(in_book_search_ui_session).to receive(:confirm)
        .and_return(success_outcome(payload: { type: :open_result, result: result }))

      expect(controller.in_book_search_confirm).to eq(:handled)
      expect(state_controller).to have_received(:jump_to_chapter_offset).with(2, 11)
      expect(in_book_search_ui_session).to have_received(:close)
    end
  end
end
