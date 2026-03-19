# frozen_string_literal: true

require 'spec_helper'

class ReaderPaginationStoreAdapterTestState
  attr_reader :current_state_calls

  def initialize(reader: {})
    @current_state = {
      reader: Shoko::Core::Models::Session::Schema.reader_state_defaults.merge(reader),
    }
    @current_state_calls = 0
  end

  def current_state
    @current_state_calls += 1
    raise 'ReaderPaginationStoreAdapter should not read full current_state'
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

RSpec.describe Shoko::Adapters::Runtime::SessionState::ReaderPaginationStoreAdapter do
  it 'reads pagination fields directly' do
    state = ReaderPaginationStoreAdapterTestState.new(
      reader: {
        total_pages: 12,
        page_map: [3, 4, 5],
        last_width: 120,
        last_height: 40,
      }
    )
    store = described_class.new(state)

    expect(store.total_pages).to eq(12)
    expect(store.page_map).to eq([3, 4, 5])
    expect(store.last_width).to eq(120)
    expect(store.last_height).to eq(40)
    expect(state.current_state_calls).to eq(0)
  end

  it 'supports update with pagination-backed state' do
    state = ReaderPaginationStoreAdapterTestState.new
    store = described_class.new(state)

    saved = store.update do |snapshot|
      snapshot.with(
        total_pages: 9,
        page_map: [4, 5],
        last_width: 100,
        last_height: 32
      )
    end

    expect(saved.total_pages).to eq(9)
    expect(store.load.page_map).to eq([4, 5])
    expect(store.load.last_width).to eq(100)
    expect(store.load.last_height).to eq(32)
    expect(state.current_state_calls).to eq(0)
  end

  it 'reuses the cached snapshot until the state root changes' do
    state = ReaderPaginationStoreAdapterTestState.new
    store = described_class.new(state)

    first = store.load
    second = store.load

    expect(second).to equal(first)
  end
end
