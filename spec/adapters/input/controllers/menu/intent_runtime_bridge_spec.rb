# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::Controllers::Menu::IntentRuntimeBridge do
  let(:menu_state_reader) do
    double(
      'MenuStateReader',
      browse_selected: 0,
      download_results: [{ 'path' => '/books/a.epub' }],
      download_selected: 0,
      mode: :annotation_editor
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
      handle_character: :handled,
      handle_backspace: :handled,
      handle_enter: :handled,
      handle_move_left: :handled,
      handle_move_right: :handled,
      handle_move_up: :handled,
      handle_move_down: :handled,
      save_annotation: :saved,
      cancel_annotation: :canceled
    )
  end
  let(:cache_path_validator) { double('CachePathValidator', valid_cache_path?: true) }
  let(:input_controller) { double('InputController', activate: nil) }
  let(:input_controller_provider) { -> { input_controller } }
  let(:exit_calls) { [] }
  let(:exit_handler) { ->(code, message) { exit_calls << [code, message] } }

  subject(:bridge) do
    described_class.new(
      menu_state_reader: menu_state_reader,
      browse_screen: browse_screen,
      library_screen: library_screen,
      annotations_screen: annotations_screen,
      annotation_edit_screen: annotation_edit_screen,
      cache_path_validator: cache_path_validator,
      input_controller_provider: input_controller_provider,
      exit_handler: exit_handler
    )
  end

  it 'activates menu modes through the input controller provider' do
    bridge.activate_menu_mode(:browse)

    expect(input_controller).to have_received(:activate).with(:browse).once
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

  it 'routes annotation editor actions to the edit screen when active' do
    expect(bridge.append_annotation_text('x')).to eq(:handled)
    expect(bridge.save_annotation).to eq(:saved)
    expect(bridge.cancel_annotation).to eq(:canceled)
  end

  it 'delegates quit_application through the injected exit handler' do
    bridge.quit_application(code: 2, message: 'bye')

    expect(exit_calls).to eq([[2, 'bye']])
  end
end
