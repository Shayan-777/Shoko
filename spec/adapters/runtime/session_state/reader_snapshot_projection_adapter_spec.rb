# frozen_string_literal: true

require 'spec_helper'

class ReaderSnapshotProjectionAdapterTestState
  attr_reader :current_state_calls

  def initialize(reader: {}, ui_state: {})
    @current_state = {
      reader: SpecSupport::StateFixtures::READER_DEFAULTS.merge(reader),
      ui: SpecSupport::StateFixtures::UI_DEFAULTS.merge(ui_state),
    }
    @current_state_calls = 0
  end

  def current_state
    @current_state_calls += 1
    raise 'ReaderSnapshotProjectionAdapter should not read full current_state'
  end

  def peek_at(*path)
    Array(path).flatten.reduce(@current_state) { |state, key| state&.dig(key) }
  end

  def peek
    @current_state
  end

  def update(updates)
    next_state = @current_state.transform_values { |value| value.is_a?(Hash) ? value.dup : value }
    updates.each do |path, value|
      root, field = path
      next_state[root][field] = value
    end
    @current_state = next_state
  end
end

RSpec.describe Shoko::Adapters::Runtime::SessionState::ReaderSnapshotProjectionAdapter do
  it 'merges session, view, pagination, and live ui state into a broad reader snapshot' do
    state = ReaderSnapshotProjectionAdapterTestState.new(
      reader: {
        current_chapter: 2,
        current_page_index: 5,
        page_map: [3, 4],
        total_pages: 7,
        sidebar_visible: true,
        dictionary_visible: true,
        running: false,
      },
      ui_state: {
        loading_active: true,
        loading_message: 'Loading',
        loading_progress: 0.75,
      }
    )
    component_registry = Shoko::Adapters::Ui::State::ReaderComponentRegistry.new
    popup_menu = Object.new
    component_registry.write(popup_menu: popup_menu)

    reader_session_store = Shoko::Adapters::Runtime::SessionState::ReaderSessionStoreAdapter.new(state)
    reader_view_state_store = Shoko::Adapters::Runtime::SessionState::ReaderViewStateStoreAdapter.new(state)
    reader_pagination_store = Shoko::Adapters::Runtime::SessionState::ReaderPaginationStoreAdapter.new(state)
    reader_state_reader = described_class.new(
      state: state,
      reader_session_store: reader_session_store,
      reader_view_state_store: reader_view_state_store,
      reader_pagination_store: reader_pagination_store,
      component_registry: component_registry
    )

    snapshot = reader_state_reader.load

    expect(snapshot.current_chapter).to eq(2)
    expect(snapshot.current_page_index).to eq(5)
    expect(snapshot.page_map).to eq([3, 4])
    expect(snapshot.total_pages).to eq(7)
    expect(snapshot.sidebar_visible).to be(true)
    expect(snapshot.dictionary_visible).to be(true)
    expect(snapshot.loading_active).to be(true)
    expect(snapshot.loading_message).to eq('Loading')
    expect(snapshot.loading_progress).to eq(0.75)
    expect(reader_state_reader.popup_menu).to equal(popup_menu)
    expect(reader_state_reader.running?).to be(false)
    expect(state.current_state_calls).to eq(0)
  end

  it 'reuses the cached snapshot until the state root changes' do
    state = ReaderSnapshotProjectionAdapterTestState.new
    reader_session_store = Shoko::Adapters::Runtime::SessionState::ReaderSessionStoreAdapter.new(state)
    reader_view_state_store = Shoko::Adapters::Runtime::SessionState::ReaderViewStateStoreAdapter.new(state)
    reader_pagination_store = Shoko::Adapters::Runtime::SessionState::ReaderPaginationStoreAdapter.new(state)
    reader_state_reader = described_class.new(
      state: state,
      reader_session_store: reader_session_store,
      reader_view_state_store: reader_view_state_store,
      reader_pagination_store: reader_pagination_store
    )

    first = reader_state_reader.load
    second = reader_state_reader.load

    expect(second).to equal(first)
  end
end
