# frozen_string_literal: true

require 'spec_helper'

class ReaderSessionStoreAdapterTestState
  attr_reader :current_state_calls

  def initialize(reader: {}, ui_state: {})
    @current_state = {
      reader: Shoko::Core::Models::Session::Schema.reader_state_defaults.merge(reader),
      ui: Shoko::Core::Models::Session::Schema.ui_state_defaults.merge(ui_state),
    }
    @current_state_calls = 0
  end

  def current_state
    @current_state_calls += 1
    raise 'ReaderSessionStoreAdapter should not read full current_state'
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

RSpec.describe Shoko::Adapters::Runtime::SessionState::ReaderSessionStoreAdapter do
  it 'reads session snapshot fields directly' do
    state = ReaderSessionStoreAdapterTestState.new(
      reader: {
        current_chapter: 3,
        mode: :dictionary,
        running: false,
      }
    )
    store = described_class.new(state)

    expect(store.current_chapter).to eq(3)
    expect(store.mode).to eq(:dictionary)
    expect(store.running?).to be(false)
    expect(state.current_state_calls).to eq(0)
  end

  it 'supports update with session-backed state' do
    state = ReaderSessionStoreAdapterTestState.new
    store = described_class.new(state)

    saved = store.update do |snapshot|
      snapshot.with(
        current_page_index: 8,
        mode: :search,
        running: false
      )
    end

    expect(saved.current_page_index).to eq(8)
    expect(store.load.mode).to eq(:search)
    expect(store.load.running).to be(false)
    expect(state.current_state_calls).to eq(0)
  end

  it 'reuses the cached snapshot until the state root changes' do
    state = ReaderSessionStoreAdapterTestState.new
    store = described_class.new(state)

    first = store.load
    second = store.load

    expect(second).to equal(first)
  end
end
