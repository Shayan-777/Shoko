# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Ui::Sessions::InBookSearchUiSessionAdapter do
  let(:popup) do
    instance_double(Shoko::Adapters::Ui::Components::InBookSearchPopupComponent, update_color_mode: nil, update_rendered_lines: nil)
  end
  let(:reader_state_reader) { instance_double(Shoko::Adapters::Runtime::SessionState::ReaderSnapshotProjectionAdapter, in_book_search_popup: popup, mode: :in_book_search) }
  let(:reader_session_mutator) { instance_double(Shoko::Adapters::Runtime::SessionState::ReaderSessionMutator, update_reader: nil) }
  let(:rendered_content_reader) { instance_double(Shoko::Application::Ports::Outbound::RenderedContentReader, rendered_lines: rendered_lines) }
  let(:rendered_lines) { { 'line-key' => { geometry: double('Geometry') } } }
  let(:ui_component_factory) { instance_double(Shoko::Adapters::Ui::ComponentFactory, in_book_search_popup: popup) }
  let(:logger) { instance_double(Shoko::Application::Ports::Outbound::Logging, error: nil) }

  subject(:session) do
    described_class.new(
      reader_state_reader: reader_state_reader,
      reader_session_mutator: reader_session_mutator,
      ui_component_factory: ui_component_factory,
      rendered_content_reader: rendered_content_reader,
      logger: logger
    )
  end

  it 'opens the search popup, resets search state, and enters search mode' do
    outcome = session.open

    expect(outcome).to be_a(Shoko::Shared::Contracts::SessionOutcome)
    expect(outcome.ok).to be(true)
    expect(outcome.code).to eq(:in_book_search_opened)
    expect(popup).to have_received(:update_rendered_lines).with(rendered_lines)
    expect(reader_session_mutator).to have_received(:update_reader).with(
      in_book_search_popup: popup,
      mode: :in_book_search,
      popup_menu: nil,
      search_query: '',
      search_results: [],
      search_results_query: '',
      search_selected_index: 0,
      search_total_matches: 0
    )
  end

  it 'publishes search results to state' do
    outcome = session.apply_results(query: 'many', results: [{ match: 'many' }], total_matches: 3)

    expect(outcome.ok).to be(true)
    expect(outcome.code).to eq(:in_book_search_results_applied)
    expect(reader_session_mutator).to have_received(:update_reader).with(
      search_query: 'many',
      search_results: [{ match: 'many' }],
      search_results_query: 'many',
      search_total_matches: 3
    )
  end

  it 'closes the popup, clears search state, and returns to read mode' do
    outcome = session.close

    expect(outcome.ok).to be(true)
    expect(outcome.code).to eq(:in_book_search_closed)
    expect(reader_session_mutator).to have_received(:update_reader).with(
      in_book_search_popup: nil,
      mode: :read,
      search_query: '',
      search_results: [],
      search_results_query: '',
      search_selected_index: 0,
      search_total_matches: 0
    )
  end

  it 'reports visibility from the reader mode' do
    expect(session.visible?).to be(true)

    allow(reader_state_reader).to receive(:mode).and_return(:read)
    expect(session.visible?).to be(false)
  end

  it 'returns a failure outcome and logs when a state write raises' do
    allow(reader_session_mutator).to receive(:update_reader).and_raise(RuntimeError, 'boom')

    outcome = session.apply_results(query: 'x', results: [], total_matches: 0)

    expect(outcome.ok).to be(false)
    expect(outcome.code).to eq(:in_book_search_apply_results_failed)
    expect(outcome.message).to eq('boom')
    expect(logger).to have_received(:error).with(
      'in_book_search.session.apply_results',
      hash_including(error: 'RuntimeError', message: 'boom')
    )
  end

  it 'refreshes popup theme mode' do
    session.refresh_theme(color_mode: :light)
    expect(popup).to have_received(:update_color_mode).with(:light)
  end
end
