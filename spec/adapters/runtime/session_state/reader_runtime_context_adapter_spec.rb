# frozen_string_literal: true

require 'spec_helper'

module ReaderRuntimeContextAdapterSpecSupport
  class TerminalSession
    def initialize(width:, height:)
      @width = width
      @height = height
    end

    def size
      [@height, @width]
    end
  end

  class DisplayCapabilities
    def kitty_images_enabled?(config)
      config.kitty_images == true
    end
  end

  class State
    attr_reader :current_state_calls

    def initialize(config: {}, reader: {}, ui_state: {})
      @current_state = {
        config: SpecSupport::StateFixtures::CONFIG_DEFAULTS.merge(config),
        reader: SpecSupport::StateFixtures::READER_DEFAULTS.merge(reader),
        ui: SpecSupport::StateFixtures::UI_DEFAULTS.merge(ui_state),
      }
      @current_state_calls = 0
    end

    def current_state
      @current_state_calls += 1
      raise 'Runtime context stores should not read full current_state'
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

    def save_config; end
  end
end

RSpec.describe Shoko::Adapters::Runtime::SessionState::ReaderRuntimeContextAdapter do
  it 'exposes terminal size, loading state, and display capabilities' do
    state = ReaderRuntimeContextAdapterSpecSupport::State.new(
      config: { kitty_images: true },
      reader: { last_width: 80, last_height: 24 },
      ui_state: { loading_message: 'Loading', loading_progress: 0.5 }
    )
    runtime_context = described_class.new(
      terminal_session: ReaderRuntimeContextAdapterSpecSupport::TerminalSession.new(width: 120, height: 40),
      display_capabilities: ReaderRuntimeContextAdapterSpecSupport::DisplayCapabilities.new,
      app_config_store: Shoko::Adapters::Runtime::SessionState::AppConfigStoreAdapter.new(state),
      reader_view_state_store: Shoko::Adapters::Runtime::SessionState::ReaderViewStateStoreAdapter.new(state),
      reader_pagination_store: Shoko::Adapters::Runtime::SessionState::ReaderPaginationStoreAdapter.new(state)
    )

    expect(runtime_context.terminal_width).to eq(120)
    expect(runtime_context.terminal_height).to eq(40)
    expect(runtime_context.loading_message).to eq('Loading')
    expect(runtime_context.loading_progress).to eq(0.5)
    expect(runtime_context.terminal_size_changed?(80, 24)).to be(false)
    expect(runtime_context.terminal_size_changed?(120, 40)).to be(true)
    expect(runtime_context.display_capabilities.kitty_images_enabled?).to be(true)
    expect(state.current_state_calls).to eq(0)
  end
end
