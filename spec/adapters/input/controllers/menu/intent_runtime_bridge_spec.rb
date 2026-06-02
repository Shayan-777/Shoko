# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::Controllers::Menu::IntentRuntimeBridge do
  let(:menu_state_reader) do
    double(
      'MenuStateReader',
      browse_selected: 0,
      download_results: [{ 'path' => '/books/a.epub' }],
      download_selected: 0,
      mode: :annotation_editor,
      translator_focus: :input
    )
  end
  let(:browse_screen) { double('BrowseScreen', filtered_count: 2) }
  let(:library_item) { double('LibraryItem', open_path: '/books/a.cache') }
  let(:library_screen) { double('LibraryScreen', items: [library_item]) }
  let(:annotations_screen) do
    double(
      'AnnotationsScreen',
      navigate: nil,
      current_annotation: { id: 1, text: 'hi' },
      current_book_path: '/books/a.epub'
    )
  end
  let(:annotation_edit_screen) do
    double(
      'AnnotationEditScreen',
      handle_move_left: :handled,
      handle_move_right: :handled,
      handle_move_up: :handled,
      handle_move_down: :handled
    )
  end
  let(:translator_screen) do
    double(
      'TranslatorScreen',
      handle_move_left: :handled,
      handle_move_right: :handled,
      handle_move_up: :handled,
      handle_move_down: :handled
    )
  end
  let(:cache_path_validator) { double('CachePathValidator', valid_cache_path?: true) }
  let(:exit_calls) { [] }
  let(:exit_handler) { ->(code, message) { exit_calls << [code, message] } }

  subject(:bridge) do
    described_class.new(
      menu_state_reader: menu_state_reader,
      browse_screen: browse_screen,
      library_screen: library_screen,
      annotations_screen: annotations_screen,
      annotation_edit_screen: annotation_edit_screen,
      translator_screen: translator_screen,
      cache_path_validator: cache_path_validator,
      exit_handler: exit_handler
    )
  end

  it 'uses the cache validator when resolving the selected library path' do
    expect(bridge.selected_library_path).to eq('/books/a.cache')
    expect(cache_path_validator).to have_received(:valid_cache_path?).with('/books/a.cache').once
  end

  it 'reads selected download results from the menu state reader' do
    expect(bridge.selected_download_result).to eq({ 'path' => '/books/a.epub' })
  end

  it 'builds selected annotation context from the annotations screen' do
    expect(bridge.selected_annotation_context).to eq(
      annotation: { id: 1, text: 'hi' },
      book_path: '/books/a.epub'
    )
  end

  it 'routes annotation cursor moves to the edit screen when active' do
    expect(bridge.move_annotation_cursor(direction: :left)).to eq(:handled)
    expect(bridge.move_annotation_cursor(direction: :down)).to eq(:handled)
  end

  it 'routes translator cursor moves to the translator screen while editing its input' do
    allow(menu_state_reader).to receive(:mode).and_return(:translator)

    expect(bridge.move_translator_cursor(direction: :left)).to eq(:handled)
    expect(translator_screen).to have_received(:handle_move_left)
  end

  it 'ignores translator cursor moves when the input is not focused' do
    allow(menu_state_reader).to receive_messages(mode: :translator, translator_focus: :source)

    expect(bridge.move_translator_cursor(direction: :left)).to eq(:pass)
    expect(translator_screen).not_to have_received(:handle_move_left)
  end

  it 'delegates quit_application through the injected exit handler' do
    bridge.quit_application(code: 2, message: 'bye')

    expect(exit_calls).to eq([[2, 'bye']])
  end
end
