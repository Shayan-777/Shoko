# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Controllers::InBookSearchController do
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
  let(:ui_factory) { instance_double('UIFactory', in_book_search_popup: popup) }
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
      ui_component_factory: ui_factory,
      document: nil,
      input_controller: input_controller,
      reader_controller: reader_controller,
      state_controller: state_controller,
      notification_service: nil,
      logger: nil,
      search_service: search_service
    )
  end

  describe '#open_in_book_search' do
    it 'shows popup, updates state, and activates modal mode' do
      expect(controller.open_in_book_search).to eq(:handled)

      expect(popup).to have_received(:show).with(query: '', results: [], total_matches: 0)
      expect(state_writer).to have_received(:update_reader).with(
        in_book_search_popup: popup,
        mode: :in_book_search,
        popup_menu: nil
      )
      expect(input_controller).to have_received(:enter_modal_mode).with(:in_book_search)
    end
  end

  describe '#handle_in_book_search_key' do
    it 'does not run search while typing' do
      allow(popup).to receive(:handle_key).with('m').and_return(type: :query_change, query: 'many')

      expect(controller.handle_in_book_search_key('m')).to eq(:handled)
      expect(search_service).not_to have_received(:search)
      expect(popup).not_to have_received(:update)
    end

    it 'runs search on submit_query' do
      allow(popup).to receive(:handle_key).with("\n").and_return(type: :submit_query, query: 'many')

      expect(controller.handle_in_book_search_key("\n")).to eq(:handled)
      expect(search_service).to have_received(:search).with('many')
      expect(popup).to have_received(:update).with(
        query: 'many',
        results: [{ match: 'many' }],
        total_matches: 1,
        results_query: 'many'
      )
    end

    it 'closes popup on close event' do
      allow(popup).to receive(:handle_key).with("\e").and_return(type: :close)

      expect(controller.handle_in_book_search_key("\e")).to eq(:handled)
      expect(popup).to have_received(:hide)
      expect(state_writer).to have_received(:update_reader).with(in_book_search_popup: nil, mode: :read)
      expect(input_controller).to have_received(:exit_modal_mode).with(:in_book_search)
    end

    it 'jumps to selected result and closes popup on open_result' do
      result = { chapter_index: 2, line_index: 11, chapter_title: 'Third' }
      allow(popup).to receive(:handle_key).with("\n").and_return(type: :open_result, result: result)

      expect(controller.handle_in_book_search_key("\n")).to eq(:handled)
      expect(state_controller).to have_received(:jump_to_chapter_offset).with(2, 11)
      expect(popup).to have_received(:hide)
      expect(state_writer).to have_received(:update_reader).with(in_book_search_popup: nil, mode: :read)
    end
  end
end
