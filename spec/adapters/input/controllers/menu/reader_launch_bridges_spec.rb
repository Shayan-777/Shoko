# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::Controllers::Menu::ReaderLaunchPortsAdapter do
  let(:menu) do
    instance_double(
      'MenuController',
      switch_to_mode: nil,
      selected_book_for_reader_launch: { 'path' => '/books/a.epub' },
      filtered_epubs: [{ 'path' => '/books/a.epub' }]
    )
  end
  let(:menu_session_store) do
    Class.new do
      include Shoko::Core::Ports::Outbound::MenuSessionStore

      def initialize(snapshot)
        @snapshot = snapshot
      end

      def load
        @snapshot
      end

      def save(snapshot)
        @snapshot = snapshot
      end
    end.new(Shoko::Core::Models::Session::MenuSnapshot.build)
  end
  let(:reader_controller) { instance_double('ReaderController', run: :handled) }
  let(:reader_controller_builder) { double('ReaderControllerBuilder', call: reader_controller) }

  subject(:adapter) do
    described_class.new(
      menu: menu,
      menu_session_store: menu_session_store,
      reader_controller_builder: reader_controller_builder
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

    expect(menu).to have_received(:switch_to_mode).with(:browse).once
  end

  it 'builds a menu progress presenter from the menu session store' do
    presenter = adapter.build

    expect(presenter).to be_a(Shoko::Application::Workflows::Menu::MenuProgressPresenter)
  end
end
