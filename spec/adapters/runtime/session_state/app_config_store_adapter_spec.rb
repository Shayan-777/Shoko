# frozen_string_literal: true

require 'spec_helper'

class AppConfigStoreAdapterTestState
  attr_reader :saved_config_count, :current_state_calls

  def initialize(config: {})
    @current_state = {
      config: Shoko::Core::Models::Session::Schema::CONFIG_DEFAULTS.merge(config),
    }
    @saved_config_count = 0
    @current_state_calls = 0
  end

  def current_state
    @current_state_calls += 1
    raise 'AppConfigStoreAdapter should not read full current_state'
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

  def save_config
    @saved_config_count += 1
  end
end

RSpec.describe Shoko::Adapters::Runtime::SessionState::AppConfigStoreAdapter do
  it 'reads config fields directly from the current snapshot' do
    state = AppConfigStoreAdapterTestState.new
    store = described_class.new(state)

    expect(store.theme).to eq(:default)
    expect(store.line_spacing).to eq(:normal)

    store.save(store.load.with(theme: :gray, line_spacing: :relaxed))

    expect(store.theme).to eq(:gray)
    expect(store.line_spacing).to eq(:relaxed)
    expect(state.saved_config_count).to eq(1)
    expect(state.current_state_calls).to eq(0)
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
    expect(state.current_state_calls).to eq(0)
  end

  it 'reuses the cached snapshot until the state root changes' do
    state = AppConfigStoreAdapterTestState.new
    store = described_class.new(state)

    first = store.load
    second = store.load

    expect(second).to equal(first)
  end
end
