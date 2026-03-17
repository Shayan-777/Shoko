# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Runtime::SessionState::ReaderRuntimeContextAdapter do
  class ReaderRuntimeContextAdapterTestTerminalSession
    def initialize(width:, height:)
      @width = width
      @height = height
    end

    def size
      [@height, @width]
    end
  end

  class ReaderRuntimeContextAdapterTestDisplayCapabilities
    def kitty_images_enabled?(config)
      config.kitty_images == true
    end
  end

  class ReaderRuntimeContextAdapterTestState
    def initialize(config: {}, reader: {}, ui: {})
      @current_state = {
        config: Shoko::Core::Models::Session::Schema::CONFIG_DEFAULTS.merge(config),
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

    def save_config; end
  end

  it 'exposes terminal size, loading state, and display capabilities' do
    state = ReaderRuntimeContextAdapterTestState.new(
      config: { kitty_images: true },
      reader: { last_width: 80, last_height: 24 },
      ui: { loading_message: 'Loading', loading_progress: 0.5 }
    )
    runtime_context = described_class.new(
      terminal_session: ReaderRuntimeContextAdapterTestTerminalSession.new(width: 120, height: 40),
      display_capabilities: ReaderRuntimeContextAdapterTestDisplayCapabilities.new,
      app_config_store: Shoko::Adapters::Runtime::SessionState::AppConfigStoreAdapter.new(state),
      reader_session_store: Shoko::Adapters::Runtime::SessionState::ReaderSessionStoreAdapter.new(state)
    )

    expect(runtime_context.terminal_width).to eq(120)
    expect(runtime_context.terminal_height).to eq(40)
    expect(runtime_context.loading_message).to eq('Loading')
    expect(runtime_context.loading_progress).to eq(0.5)
    expect(runtime_context.terminal_size_changed?(80, 24)).to be(false)
    expect(runtime_context.terminal_size_changed?(120, 40)).to be(true)
    expect(runtime_context.display_capabilities.kitty_images_enabled?).to be(true)
  end
end
