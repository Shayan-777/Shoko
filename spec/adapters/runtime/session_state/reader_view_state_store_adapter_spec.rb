# frozen_string_literal: true

require 'spec_helper'

class ReaderViewStateStoreAdapterTestState
  attr_reader :current_state_calls

  def initialize(reader: {}, ui_state: {})
    @current_state = {
      reader: SpecSupport::StateFixtures::READER_DEFAULTS.merge(reader),
      ui: SpecSupport::StateFixtures::UI_DEFAULTS.merge(ui_state),
    }
    @current_state_calls = 0
  end

  def current_state
    @current_state_calls += 1
    raise 'ReaderViewStateStoreAdapter should not read full current_state'
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

RSpec.describe Shoko::Adapters::Runtime::SessionState::ReaderViewStateStoreAdapter do
  it 'reads view-state fields directly' do
    state = ReaderViewStateStoreAdapterTestState.new(
      reader: {
        dictionary_visible: true,
        annotations_overlay_selected: 2,
      },
      ui_state: {
        loading_active: true,
        loading_message: 'Loading',
        loading_progress: 0.5,
      }
    )
    store = described_class.new(state)

    expect(store.dictionary_visible?).to be(true)
    expect(store.annotations_overlay_selected).to eq(2)
    expect(store.loading_active?).to be(true)
    expect(store.loading_message).to eq('Loading')
    expect(store.loading_progress).to eq(0.5)
    expect(state.current_state_calls).to eq(0)
  end

  it 'supports update with mixed reader and ui-backed fields' do
    state = ReaderViewStateStoreAdapterTestState.new
    store = described_class.new(state)

    saved = store.update do |snapshot|
      snapshot.with(
        dictionary_visible: true,
        annotations_overlay_selected: 1,
        loading_active: true,
        loading_message: 'Paginating',
        loading_progress: 0.25
      )
    end

    expect(saved.dictionary_visible).to be(true)
    expect(store.load.annotations_overlay_selected).to eq(1)
    expect(store.load.loading_active).to be(true)
    expect(store.load.loading_message).to eq('Paginating')
    expect(store.load.loading_progress).to eq(0.25)
    expect(state.current_state_calls).to eq(0)
  end

  it 'reuses the cached snapshot until the state root changes' do
    state = ReaderViewStateStoreAdapterTestState.new
    store = described_class.new(state)

    first = store.load
    second = store.load

    expect(second).to equal(first)
  end
end
