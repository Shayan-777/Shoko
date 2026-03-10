# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Runtime::SessionState::ReaderUiStateView do
  class ReaderUiStateViewTestReaderSessionStore
    include Shoko::Core::Ports::Outbound::ReaderSessionStore

    def initialize(snapshot = Shoko::Core::Models::Session::ReaderSnapshot.build)
      @snapshot = snapshot
    end

    def load
      @snapshot
    end

    def save(snapshot)
      @snapshot = snapshot
    end
  end

  class ReaderUiStateViewTestReaderRuntimeContext
    include Shoko::Core::Ports::Outbound::ReaderRuntimeContext

    def initialize(width: 80, height: 24)
      @width = width
      @height = height
    end

    def terminal_size
      Shoko::Core::Models::Session::TerminalSize.build(width: @width, height: @height)
    end

    def display_capabilities
      Shoko::Core::Models::Session::DisplayCapabilitiesSnapshot.build(kitty_images_enabled: false)
    end
  end

  it 'reads terminal size from runtime context and loading state from reader session' do
    store = ReaderUiStateViewTestReaderSessionStore.new(
      Shoko::Core::Models::Session::ReaderSnapshot.build(
        last_width: 80,
        last_height: 24,
        loading_message: 'Loading',
        loading_progress: 0.5
      )
    )
    runtime_context = ReaderUiStateViewTestReaderRuntimeContext.new(width: 120, height: 40)
    view = described_class.new(
      reader_session_store: store,
      reader_runtime_context: runtime_context
    )

    expect(view.terminal_width).to eq(120)
    expect(view.terminal_height).to eq(40)
    expect(view.loading_message).to eq('Loading')
    expect(view.loading_progress).to eq(0.5)
    expect(view.terminal_size_changed?(80, 24)).to be(false)
    expect(view.terminal_size_changed?(120, 40)).to be(true)
  end
end
