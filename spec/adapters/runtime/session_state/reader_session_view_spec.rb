# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Runtime::SessionState::ReaderSessionView do
  class ReaderSessionViewTestReaderSessionStore
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

  it 'reads the current reader snapshot dynamically' do
    store = ReaderSessionViewTestReaderSessionStore.new
    view = described_class.new(reader_session_store: store)

    expect(view.current_chapter).to eq(0)
    expect(view.sidebar_visible?).to be(false)
    expect(view.running?).to be(true)

    store.save(store.load.with(
                 current_chapter: 3,
                 sidebar_visible: true,
                 sidebar_prev_view_mode: :split,
                 sidebar_toc_filter_active: true,
                 running: false
               ))

    expect(view.current_chapter).to eq(3)
    expect(view.sidebar_visible?).to be(true)
    expect(view.sidebar_prev_view_mode).to eq(:split)
    expect(view.sidebar_toc_filter_active?).to be(true)
    expect(view.running?).to be(false)
  end
end
