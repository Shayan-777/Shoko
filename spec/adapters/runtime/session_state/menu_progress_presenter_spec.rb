# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Runtime::SessionState::MenuProgressPresenter do
  class MenuProgressPresenterTestMenuSessionStore
    include Shoko::Application::Ports::Outbound::MenuSessionStore

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

  class MenuProgressPresenterTestMenuTransientStore
    include Shoko::Application::Ports::Outbound::MenuTransientStore

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

  let(:menu_session_store) do
    MenuProgressPresenterTestMenuSessionStore.new(Shoko::Application::Ports::Outbound::State::MenuSessionSnapshot.build)
  end
  let(:menu_transient_store) do
    MenuProgressPresenterTestMenuTransientStore.new(Shoko::Application::Ports::Outbound::State::MenuTransientSnapshot.build)
  end

  subject(:presenter) { described_class.new(menu_session_store, menu_transient_store) }

  it 'writes loading state across session and transient stores when shown and cleared' do
    presenter.show(path: '/books/a.epub', index: 2, mode: :browse)

    expect(menu_session_store.load.loading_path).to eq('/books/a.epub')
    expect(menu_session_store.load.loading_index).to eq(2)
    expect(menu_session_store.load.loading_mode).to eq(:browse)
    expect(menu_transient_store.load.loading_active).to be(true)
    expect(menu_transient_store.load.loading_message).to eq('Preparing book...')

    presenter.clear

    expect(menu_session_store.load.loading_path).to be_nil
    expect(menu_session_store.load.loading_mode).to be_nil
    expect(menu_transient_store.load.loading_active).to be(false)
    expect(menu_transient_store.load.loading_message).to be_nil
  end

  it 'rolls back the session slice if transient persistence fails' do
    failing_transient_store = Class.new(MenuProgressPresenterTestMenuTransientStore) do
      def save(_snapshot)
        raise ArgumentError, 'boom'
      end
    end.new(Shoko::Application::Ports::Outbound::State::MenuTransientSnapshot.build)

    presenter = described_class.new(menu_session_store, failing_transient_store)

    expect do
      presenter.show(path: '/books/a.epub', index: 2, mode: :browse)
    end.to raise_error(ArgumentError, 'boom')

    expect(menu_session_store.load).to eq(Shoko::Application::Ports::Outbound::State::MenuSessionSnapshot.build)
  end
end
