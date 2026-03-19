# frozen_string_literal: true

require 'spec_helper'

class MenuSnapshotProjectionAdapterTestState
  attr_reader :current_state_calls

  def initialize(menu: {})
    @current_state = {
      menu: Shoko::Core::Models::Session::Schema::MENU_DEFAULTS.merge(menu),
    }
    @current_state_calls = 0
  end

  def current_state
    @current_state_calls += 1
    raise 'MenuSnapshotProjectionAdapter should not read full current_state'
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

RSpec.describe Shoko::Adapters::Runtime::SessionState::MenuSnapshotProjectionAdapter do
  it 'merges session and transient slices into a broad menu snapshot' do
    state = MenuSnapshotProjectionAdapterTestState.new
    menu_session_store = Shoko::Adapters::Runtime::SessionState::MenuSessionStoreAdapter.new(state)
    menu_transient_store = Shoko::Adapters::Runtime::SessionState::MenuTransientStoreAdapter.new(state)
    store = described_class.new(
      state: state,
      menu_session_store: menu_session_store,
      menu_transient_store: menu_transient_store
    )

    menu_session_store.save(menu_session_store.load.with(mode: :download, download_selected: 2))
    menu_transient_store.save(
      menu_transient_store.load.with(
        download_results: [{ title: 'Emma' }],
        loading_active: true,
        loading_message: 'Preparing'
      )
    )

    snapshot = store.load

    expect(snapshot).to be_a(Shoko::Core::Models::Session::MenuSnapshot)
    expect(snapshot.mode).to eq(:download)
    expect(snapshot.download_selected).to eq(2)
    expect(snapshot.download_results).to eq([{ title: 'Emma' }])
    expect(store.dictionary_entries).to eq([])
    expect(store.loading_active?).to be(true)
    expect(store.loading_message).to eq('Preparing')
    expect(state.current_state_calls).to eq(0)
  end

  it 'reuses the cached snapshot until the root changes' do
    state = MenuSnapshotProjectionAdapterTestState.new
    menu_session_store = Shoko::Adapters::Runtime::SessionState::MenuSessionStoreAdapter.new(state)
    menu_transient_store = Shoko::Adapters::Runtime::SessionState::MenuTransientStoreAdapter.new(state)
    store = described_class.new(
      state: state,
      menu_session_store: menu_session_store,
      menu_transient_store: menu_transient_store
    )

    first = store.load
    second = store.load
    menu_transient_store.save(menu_transient_store.load.with(download_message: 'Updated'))
    third = store.load

    expect(second).to equal(first)
    expect(third).not_to equal(first)
    expect(third.download_message).to eq('Updated')
  end
end
