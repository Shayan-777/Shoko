# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Runtime::SessionState::ReaderSessionStoreAdapter do
  class ReaderSessionStoreAdapterTestState
    def initialize(reader: {}, ui: {})
      @current_state = {
        reader: Shoko::Core::Models::Session::Schema.reader_state_defaults.merge(reader),
        ui: Shoko::Core::Models::Session::Schema.ui_state_defaults.merge(ui)
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

  let(:ui_session_registry) { Shoko::Adapters::Runtime::SessionState::ReaderUiSessionRegistry.new }

  it 'reads snapshot fields and live ui fields directly' do
    state = ReaderSessionStoreAdapterTestState.new(
      reader: {
        current_chapter: 3,
        sidebar_visible: true,
        sidebar_prev_view_mode: :split,
        sidebar_toc_filter_active: true,
        running: false
      }
    )
    store = described_class.new(state, ui_session_registry: ui_session_registry)
    popup = Object.new

    ui_session_registry.write(dictionary_popup: popup)

    expect(store.current_chapter).to eq(3)
    expect(store.sidebar_visible?).to be(true)
    expect(store.sidebar_prev_view_mode).to eq(:split)
    expect(store.sidebar_toc_filter_active?).to be(true)
    expect(store.running?).to be(false)
    expect(store.dictionary_popup).to equal(popup)
    expect(store.popup_menu).to be_nil
  end

  it 'supports update with ui-backed loading state' do
    state = ReaderSessionStoreAdapterTestState.new
    store = described_class.new(state, ui_session_registry: ui_session_registry)

    saved = store.update do |snapshot|
      snapshot.with(
        current_page_index: 8,
        loading_active: true,
        loading_message: 'Loading',
        loading_progress: 0.5
      )
    end

    expect(saved.current_page_index).to eq(8)
    expect(store.load.loading_active?).to be(true)
    expect(state.current_state[:ui][:loading_message]).to eq('Loading')
    expect(state.current_state[:ui][:loading_progress]).to eq(0.5)
  end
end
