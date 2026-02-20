# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Output::Ui::Sessions::InBookSearchUiSessionAdapter do
  let(:popup) do
    instance_double('InBookSearchPopup',
                    show: nil,
                    hide: nil,
                    visible?: true,
                    insert_char: { type: :query_change, query: 'a' },
                    backspace: { type: :query_change, query: '' },
                    confirm: { type: :submit_query, query: 'a' },
                    cancel: { type: :close },
                    scroll_up_action: { type: :scroll },
                    scroll_down_action: { type: :scroll },
                    update: nil)
  end
  let(:reader_state_reader) { instance_double('ReaderStateReader', in_book_search_popup: popup) }
  let(:state_writer) { instance_double('ReaderStateWriter', update_reader: nil) }
  let(:ui_component_factory) { instance_double('UIFactory', in_book_search_popup: popup) }
  let(:logger) { instance_double('Logger', error: nil) }

  subject(:session) do
    described_class.new(
      reader_state_reader: reader_state_reader,
      state_writer: state_writer,
      ui_component_factory: ui_component_factory,
      logger: logger
    )
  end

  it 'opens search popup and updates reader mode' do
    outcome = session.open(query: '', results: [], total_matches: 0)

    expect(outcome).to be_a(Shoko::Application::Ui::SessionOutcome)
    expect(outcome.ok).to be(true)
    expect(outcome.code).to eq(:in_book_search_opened)
    expect(popup).to have_received(:show).with(query: '', results: [], total_matches: 0)
    expect(state_writer).to have_received(:update_reader).with(
      in_book_search_popup: popup,
      mode: :in_book_search,
      popup_menu: nil
    )
  end

  it 'delegates key handling and result updates' do
    insert_outcome = session.insert_char('a')
    expect(insert_outcome.ok).to be(true)
    expect(insert_outcome.payload).to eq(type: :query_change, query: 'a')

    update_outcome = session.update(query: 'a', results: [], total_matches: 0, results_query: 'a')
    expect(update_outcome.ok).to be(true)
    expect(update_outcome.code).to eq(:in_book_search_update_handled)
    expect(popup).to have_received(:update).with(query: 'a', results: [], total_matches: 0, results_query: 'a')
  end

  it 'closes popup and returns to read mode' do
    outcome = session.close

    expect(outcome.ok).to be(true)
    expect(outcome.code).to eq(:in_book_search_closed)
    expect(popup).to have_received(:hide)
    expect(state_writer).to have_received(:update_reader).with(in_book_search_popup: nil, mode: :read)
  end

  it 'returns failure outcomes and logs when popup actions raise' do
    allow(popup).to receive(:confirm).and_raise(RuntimeError, 'boom')

    outcome = session.confirm

    expect(outcome.ok).to be(false)
    expect(outcome.code).to eq(:in_book_search_confirm_failed)
    expect(outcome.message).to eq('boom')
    expect(logger).to have_received(:error).with(
      'in_book_search.session.confirm',
      hash_including(error: 'RuntimeError', message: 'boom')
    )
  end
end
