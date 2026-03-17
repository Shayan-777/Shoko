# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Runtime::SessionState::MenuSessionStoreAdapter do
  class MenuSessionStoreAdapterTestState
    def initialize(menu: {})
      @current_state = {
        menu: Shoko::Core::Models::Session::Schema::MENU_DEFAULTS.merge(menu)
      }
    end

    def current_state
      @current_state
    end

    def update(updates)
      updates.each do |path, value|
        root, field = path
        @current_state[root][field] = value
      end
    end
  end

  it 'reads menu fields directly from the current snapshot' do
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
                 dictionary_results: ['one'],
                 loading_active: true
               ))

    expect(store.current_menu_mode).to eq(:browse)
    expect(store.selected_library_index).to eq(4)
    expect(store.search_active?).to be(true)
    expect(store.library_details_open?).to be(true)
    expect(store.dictionary_entries).to eq(['one'])
    expect(store.loading_active?).to be(true)
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
  end
end
