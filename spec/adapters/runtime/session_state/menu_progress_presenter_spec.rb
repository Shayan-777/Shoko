# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Runtime::SessionState::MenuProgressPresenter do
  class MenuProgressPresenterTestMenuSessionStore
    include Shoko::Core::Ports::Outbound::MenuSessionStore

    attr_reader :snapshot

    def initialize(snapshot)
      @snapshot = snapshot
    end

    def load
      @snapshot
    end

    def save(snapshot)
      @snapshot = snapshot
    end
  end

  let(:menu_session_store) { MenuProgressPresenterTestMenuSessionStore.new(Shoko::Core::Models::Session::MenuSnapshot.build) }

  subject(:presenter) { described_class.new(menu_session_store) }

  it 'writes loading state when shown and cleared' do
    presenter.show(path: '/books/a.epub', index: 2, mode: :browse)

    expect(menu_session_store.load.loading_active).to be(true)
    expect(menu_session_store.load.loading_path).to eq('/books/a.epub')
    expect(menu_session_store.load.loading_index).to eq(2)
    expect(menu_session_store.load.loading_mode).to eq(:browse)

    presenter.clear

    expect(menu_session_store.load.loading_active).to be(false)
    expect(menu_session_store.load.loading_path).to be_nil
    expect(menu_session_store.load.loading_message).to be_nil
  end
end
