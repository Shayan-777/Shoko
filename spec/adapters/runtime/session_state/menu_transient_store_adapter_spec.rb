# frozen_string_literal: true

require 'spec_helper'

class MenuTransientStoreAdapterTestState
  attr_reader :current_state_calls

  def initialize(menu: {})
    @current_state = {
      menu: SpecSupport::StateFixtures::MENU_DEFAULTS.merge(menu),
    }
    @current_state_calls = 0
  end

  def current_state
    @current_state_calls += 1
    raise 'MenuTransientStoreAdapter should not read full current_state'
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

RSpec.describe Shoko::Adapters::Runtime::SessionState::MenuTransientStoreAdapter do
  it 'reads transient fields directly from the current snapshot' do
    state = MenuTransientStoreAdapterTestState.new
    store = described_class.new(state)

    expect(store.download_status).to eq(:idle)
    expect(store.loading_active?).to be(false)

    store.save(store.load.with(
                 dictionary_results: ['one'],
                 download_status: :done,
                 loading_active: true,
                 loading_message: 'Preparing book...'
               ))

    expect(store.dictionary_entries).to eq(['one'])
    expect(store.download_status).to eq(:done)
    expect(store.loading_active?).to be(true)
    expect(store.loading_message).to eq('Preparing book...')
    expect(store).not_to respond_to(:current_menu_mode)
    expect(state.current_state_calls).to eq(0)
  end

  it 'supports update with load-yield-save semantics' do
    state = MenuTransientStoreAdapterTestState.new
    store = described_class.new(state)

    saved = store.update do |snapshot|
      snapshot.with(download_message: 'Done', download_progress: 1.0)
    end

    expect(saved.download_message).to eq('Done')
    expect(store.download_progress).to eq(1.0)
    expect(state.current_state_calls).to eq(0)
  end

  it 'reuses the cached snapshot until the state root changes' do
    state = MenuTransientStoreAdapterTestState.new
    store = described_class.new(state)

    first = store.load
    second = store.load

    expect(second).to equal(first)
  end
end
