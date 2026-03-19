# frozen_string_literal: true

require 'spec_helper'

class MenuSessionStoreAdapterTestState
  attr_reader :current_state_calls

  def initialize(menu: {})
    @current_state = {
      menu: Shoko::Core::Models::Session::Schema::MENU_DEFAULTS.merge(menu),
    }
    @current_state_calls = 0
  end

  def current_state
    @current_state_calls += 1
    raise 'MenuSessionStoreAdapter should not read full current_state'
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

RSpec.describe Shoko::Adapters::Runtime::SessionState::MenuSessionStoreAdapter do
  it 'reads session fields directly from the current snapshot' do
    state = MenuSessionStoreAdapterTestState.new
    store = described_class.new(state)

    expect(store.mode).to eq(:menu)
    expect(store.search_active?).to be(false)
    expect(store.wipe_cache_cached?).to be(true)

    store.save(store.load.with(
                 mode: :browse,
                 browse_selected: 4,
                 search_active: true,
                 library_details_open: true,
                 selected_annotation: { id: 'ann-1' },
                 loading_path: '/books/a.epub'
               ))

    expect(store.current_menu_mode).to eq(:browse)
    expect(store.selected_library_index).to eq(4)
    expect(store.search_active?).to be(true)
    expect(store.library_details_open?).to be(true)
    expect(store.selected_annotation_record).to eq({ id: 'ann-1' })
    expect(store.loading_path).to eq('/books/a.epub')
    expect(store).not_to respond_to(:dictionary_entries)
    expect(store).not_to respond_to(:loading_active?)
    expect(state.current_state_calls).to eq(0)
  end

  it 'supports update with load-yield-save semantics' do
    state = MenuSessionStoreAdapterTestState.new
    store = described_class.new(state)

    saved = store.update do |snapshot|
      snapshot.with(selected: 2, search_query: 'foo', search_cursor: 3)
    end

    expect(saved.selected).to eq(2)
    expect(store.search_query).to eq('foo')
    expect(store.search_cursor).to eq(3)
    expect(state.current_state_calls).to eq(0)
  end

  it 'reuses the cached snapshot until the state root changes' do
    state = MenuSessionStoreAdapterTestState.new
    store = described_class.new(state)

    first = store.load
    second = store.load

    expect(second).to equal(first)
  end
end
