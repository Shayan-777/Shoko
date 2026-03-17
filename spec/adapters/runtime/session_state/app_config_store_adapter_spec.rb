# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Runtime::SessionState::AppConfigStoreAdapter do
  class AppConfigStoreAdapterTestState
    attr_reader :saved_config_count

    def initialize(config: {})
      @current_state = {
        config: Shoko::Core::Models::Session::Schema::CONFIG_DEFAULTS.merge(config)
      }
      @saved_config_count = 0
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

    def save_config
      @saved_config_count += 1
    end
  end

  it 'reads config fields directly from the current snapshot' do
    state = AppConfigStoreAdapterTestState.new
    store = described_class.new(state)

    expect(store.theme).to eq(:default)
    expect(store.line_spacing).to eq(:normal)

    store.save(store.load.with(theme: :gray, line_spacing: :relaxed))

    expect(store.theme).to eq(:gray)
    expect(store.line_spacing).to eq(:relaxed)
    expect(state.saved_config_count).to eq(1)
  end

  it 'supports update with load-yield-save semantics' do
    state = AppConfigStoreAdapterTestState.new
    store = described_class.new(state)

    saved = store.update do |snapshot|
      snapshot.with(view_mode: :split, page_numbering_mode: :absolute)
    end

    expect(saved.view_mode).to eq(:split)
    expect(store.load.page_numbering_mode).to eq(:absolute)
    expect(state.saved_config_count).to eq(1)
  end
end
