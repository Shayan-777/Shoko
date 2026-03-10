# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Ui::Sessions::InBookSearchUiSessionAdapter do
  let(:popup) do
    instance_double('InBookSearchPopup',
                    show: nil,
                    hide: nil,
                    visible?: true,
                    update_color_mode: nil,
                    update_rendered_lines: nil,
                    insert_char: { type: :query_change, query: 'a' },
                    backspace: { type: :query_change, query: '' },
                    confirm: { type: :submit_query, query: 'a' },
                    cancel: { type: :close },
                    scroll_up_action: { type: :scroll },
                    scroll_down_action: { type: :scroll },
                    update: nil)
  end
  let(:reader_state_reader) { instance_double('ReaderStateReader', in_book_search_popup: popup) }
  let(:reader_session_mutator) { instance_double('ReaderSessionMutator', update_reader: nil) }
  let(:rendered_content_reader) { instance_double('RenderedContentReader', rendered_lines: rendered_lines) }
  let(:rendered_lines) { { 'line-key' => { geometry: double('Geometry') } } }
  let(:ui_component_factory) { instance_double('UIFactory', in_book_search_popup: popup) }
  let(:logger) { instance_double('Logger', error: nil) }

  subject(:session) do
    described_class.new(
      reader_state_reader: reader_state_reader,
      reader_session_mutator: reader_session_mutator,
      ui_component_factory: ui_component_factory,
      rendered_content_reader: rendered_content_reader,
      logger: logger
    )
  end

  it 'opens search popup and updates reader mode' do
    outcome = session.open(query: '', results: [], total_matches: 0)

    expect(outcome).to be_a(Shoko::Shared::Contracts::SessionOutcome)
    expect(outcome.ok).to be(true)
    expect(outcome.code).to eq(:in_book_search_opened)
    expect(popup).to have_received(:update_rendered_lines).with(rendered_lines)
    expect(popup).to have_received(:show).with(query: '', results: [], total_matches: 0)
    expect(reader_session_mutator).to have_received(:update_reader).with(
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
    expect(popup).to have_received(:update_rendered_lines).with(rendered_lines)
    expect(popup).to have_received(:update).with(query: 'a', results: [], total_matches: 0, results_query: 'a')
  end

  it 'closes popup and returns to read mode' do
    outcome = session.close

    expect(outcome.ok).to be(true)
    expect(outcome.code).to eq(:in_book_search_closed)
    expect(popup).to have_received(:hide)
    expect(reader_session_mutator).to have_received(:update_reader).with(in_book_search_popup: nil, mode: :read)
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

  it 'refreshes popup theme mode' do
    session.refresh_theme(color_mode: :light)
    expect(popup).to have_received(:update_color_mode).with(:light)
  end
end
