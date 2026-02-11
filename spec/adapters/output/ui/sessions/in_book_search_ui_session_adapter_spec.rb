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

  subject(:session) do
    described_class.new(
      reader_state_reader: reader_state_reader,
      state_writer: state_writer,
      ui_component_factory: ui_component_factory
    )
  end

  it 'opens search popup and updates reader mode' do
    expect(session.open(query: '', results: [], total_matches: 0)).to be(true)
    expect(popup).to have_received(:show).with(query: '', results: [], total_matches: 0)
    expect(state_writer).to have_received(:update_reader).with(
      in_book_search_popup: popup,
      mode: :in_book_search,
      popup_menu: nil
    )
  end

  it 'delegates key handling and result updates' do
    expect(session.insert_char('a')).to eq(type: :query_change, query: 'a')
    expect(session.update(query: 'a', results: [], total_matches: 0, results_query: 'a')).to be(true)
    expect(popup).to have_received(:update).with(query: 'a', results: [], total_matches: 0, results_query: 'a')
  end

  it 'closes popup and returns to read mode' do
    expect(session.close).to be(true)
    expect(popup).to have_received(:hide)
    expect(state_writer).to have_received(:update_reader).with(in_book_search_popup: nil, mode: :read)
  end
end
