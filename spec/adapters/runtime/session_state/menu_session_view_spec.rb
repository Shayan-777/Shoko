# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Runtime::SessionState::MenuSessionView do
  class MenuSessionViewTestMenuSessionStore
    include Shoko::Core::Ports::Outbound::MenuSessionStore

    def initialize(snapshot = Shoko::Core::Models::Session::MenuSnapshot.build)
      @snapshot = snapshot
    end

    def load
      @snapshot
    end

    def save(snapshot)
      @snapshot = snapshot
    end
  end

  it 'reads the current menu snapshot dynamically' do
    store = MenuSessionViewTestMenuSessionStore.new
    view = described_class.new(menu_session_store: store)

    expect(view.mode).to eq(:menu)
    expect(view.search_active?).to be(false)
    expect(view.wipe_cache_cached?).to be(true)

    store.save(store.load.with(
                 mode: :browse,
                 browse_selected: 4,
                 search_active: true,
                 library_details_open: true,
                 dictionary_results: ['one'],
                 loading_active: true
               ))

    expect(view.current_menu_mode).to eq(:browse)
    expect(view.selected_library_index).to eq(4)
    expect(view.search_active?).to be(true)
    expect(view.library_details_open?).to be(true)
    expect(view.dictionary_entries).to eq(['one'])
    expect(view.loading_active?).to be(true)
  end
end
