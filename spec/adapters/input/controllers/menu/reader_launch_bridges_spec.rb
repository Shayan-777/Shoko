# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::Controllers::Menu::ReaderLaunchPortsAdapter do
  class ReaderLaunchBridgesSpecMenuTransientStore
    include Shoko::Application::Ports::Outbound::MenuTransientStore

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

  let(:menu_state_reader) { double('MenuStateReader', browse_selected: 0) }
  let(:browse_screen) do
    double(
      'BrowseScreen',
      book_at: { 'path' => '/books/a.epub' },
      filtered_epubs: [{ 'path' => '/books/a.epub' }]
    )
  end
  let(:mode_switcher) { double('ModeSwitcher', call: nil) }
  let(:menu_session_store) do
    Class.new do
      include Shoko::Application::Ports::Outbound::MenuSessionStore

      def initialize(snapshot)
        @snapshot = snapshot
      end

      def load
        @snapshot
      end

      def save(snapshot)
        @snapshot = snapshot
      end
    end.new(Shoko::Application::Ports::Outbound::State::MenuSessionSnapshot.build)
  end
  let(:reader_controller) { instance_double(Shoko::Adapters::Input::Controllers::ReaderController, run: :handled) }
  let(:reader_controller_builder) { double('ReaderControllerBuilder', call: reader_controller) }
  let(:menu_transient_store) do
    ReaderLaunchBridgesSpecMenuTransientStore.new(Shoko::Application::Ports::Outbound::State::MenuTransientSnapshot.build)
  end

  subject(:adapter) do
    described_class.new(
      menu_state_reader: menu_state_reader,
      browse_screen: browse_screen,
      mode_switcher: mode_switcher,
      menu_session_store: menu_session_store,
      reader_controller_builder: reader_controller_builder,
      menu_transient_store: menu_transient_store
    )
  end

  it 'reads selected book from explicit menu workflow API' do
    selected = adapter.selected_book

    expect(selected).to be_a(Shoko::Core::Models::MenuBook)
    expect(selected.path).to eq('/books/a.epub')
  end

  it 'reads filtered books from explicit menu workflow API' do
    filtered = adapter.filtered_books

    expect(filtered).to all(be_a(Shoko::Core::Models::MenuBook))
    expect(filtered.map(&:path)).to eq(['/books/a.epub'])
  end

  it 'builds and runs reader controller through the provided builder' do
    result = adapter.run_reader(path: '/books/a.epub', preloaded_document: nil, background_worker: nil)

    expect(result).to eq(:handled)
    expect(reader_controller_builder).to have_received(:call).with(
      '/books/a.epub',
      preloaded_document: nil,
      background_worker: nil
    )
  end

  it 'delegates switch_mode to menu' do
    adapter.switch_mode(:browse)

    expect(mode_switcher).to have_received(:call).with(:browse).once
  end

  it 'builds a menu progress presenter from the menu session store' do
    presenter = adapter.build

    expect(presenter).to be_a(Shoko::Adapters::Input::Controllers::Menu::ReaderLaunchProgressPresenter)
  end
end
