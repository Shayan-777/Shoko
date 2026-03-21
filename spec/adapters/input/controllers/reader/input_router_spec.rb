# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::Controllers::Reader::InputRouter do
  let(:reader_state_reader) { instance_double('ReaderStateReader', popup_menu: nil) }
  let(:input_controller) { instance_double('ReaderInputController', handle_key: nil, handle_popup_menu_input: nil, handle_annotations_overlay_input: nil) }
  let(:ui_controller) do
    instance_double(
      'UIController',
      annotations_overlay_visible?: false,
      annotation_editor_visible?: false,
      dictionary_visible?: false,
      in_book_search_visible?: false,
      translation_popup_visible?: translation_popup_visible,
      handle_translation_popup_input: :handled,
      close_dictionary: :handled,
      close_in_book_search: :handled
    )
  end
  let(:key_classifier) { instance_double('KeyClassifier', cancel_key?: false) }
  let(:translation_popup_visible) { true }

  subject(:router) do
    described_class.new(
      reader_state_reader: reader_state_reader,
      input_controller: input_controller,
      ui_controller: ui_controller,
      key_classifier: key_classifier
    )
  end

  it 'routes keys to the translation popup when it is visible' do
    router.dispatch_input_keys(['j'])

    expect(ui_controller).to have_received(:handle_translation_popup_input).with(['j'])
    expect(input_controller).not_to have_received(:handle_key)
  end

  it 'falls back to normal reader input when the translation popup is hidden' do
    allow(ui_controller).to receive(:translation_popup_visible?).and_return(false)

    router.dispatch_input_keys(['j'])

    expect(input_controller).to have_received(:handle_key).with('j')
  end
end
