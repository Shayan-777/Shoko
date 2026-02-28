# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::Controllers::Menu::ReaderLaunchBookSelectionBridge do
  let(:menu) do
    instance_double(
      'MenuController',
      selected_book_for_reader_launch: { 'path' => '/books/a.epub' },
      filtered_epubs: [{ 'path' => '/books/a.epub' }]
    )
  end

  subject(:bridge) { described_class.new(menu: menu) }

  it 'reads selected book from explicit menu workflow API' do
    expect(bridge.selected_book).to eq({ 'path' => '/books/a.epub' })
  end

  it 'reads filtered books from explicit menu workflow API' do
    expect(bridge.filtered_books).to eq([{ 'path' => '/books/a.epub' }])
  end
end

RSpec.describe Shoko::Adapters::Input::Controllers::Menu::ReaderLaunchRuntimeBridge do
  let(:reader_controller) { instance_double('ReaderController', run: :handled) }
  let(:reader_controller_builder) { double('ReaderControllerBuilder', call: reader_controller) }
  let(:menu) { instance_double('MenuController', draw_screen: nil, switch_to_mode: nil) }

  subject(:bridge) do
    described_class.new(
      menu: menu,
      reader_controller_builder: reader_controller_builder
    )
  end

  it 'builds and runs reader controller through the provided builder' do
    result = bridge.run_reader(path: '/books/a.epub', preloaded_document: nil, background_worker: nil)

    expect(result).to eq(:handled)
    expect(reader_controller_builder).to have_received(:call).with(
      '/books/a.epub',
      preloaded_document: nil,
      background_worker: nil
    )
  end

  it 'delegates draw_screen and switch_mode to menu' do
    bridge.draw_screen
    bridge.switch_mode(:browse)

    expect(menu).to have_received(:draw_screen).once
    expect(menu).to have_received(:switch_to_mode).with(:browse).once
  end
end
