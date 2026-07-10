# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::Controllers::Reader::InputRouter do
  let(:reader_state_reader) { instance_double('ReaderStateReader', popup_menu: nil) }
  let(:input_controller) do
    instance_double('ReaderInputController',
                    handle_key: nil, handle_popup_menu_input: nil, handle_annotations_overlay_input: nil)
  end
  let(:ui_controller) do
    instance_double(
      'UIController',
      annotations_overlay_visible?: false,
      annotation_editor_visible?: false,
      dictionary_visible?: false,
      in_book_search_visible?: false,
      toc_lookup_visible?: false,
      translator_visible?: false,
      notes_visible?: false,
      close_dictionary: :handled,
      close_in_book_search: :handled,
      close_toc_lookup: :handled,
      close_translator_lookup: :handled
    )
  end
  let(:key_classifier) { instance_double('KeyClassifier', cancel_key?: false) }

  subject(:router) do
    described_class.new(
      reader_state_reader: reader_state_reader,
      input_controller: input_controller,
      ui_controller: ui_controller,
      key_classifier: key_classifier
    )
  end

  it 'dispatches ordinary keys to the input controller' do
    router.dispatch_input_keys(['j'])
    expect(input_controller).to have_received(:handle_key).with('j')
  end

  it 'intercepts the cancel key to close the dictionary when it is open' do
    allow(ui_controller).to receive(:dictionary_visible?).and_return(true)
    allow(key_classifier).to receive(:cancel_key?).and_return(true)

    router.dispatch_input_keys(["\e"])

    expect(ui_controller).to have_received(:close_dictionary)
    expect(input_controller).not_to have_received(:handle_key)
  end

  it 'intercepts the cancel key to close the translator when it is open' do
    allow(ui_controller).to receive(:translator_visible?).and_return(true)
    allow(key_classifier).to receive(:cancel_key?).and_return(true)

    router.dispatch_input_keys(["\e"])

    expect(ui_controller).to have_received(:close_translator_lookup)
    expect(input_controller).not_to have_received(:handle_key)
  end
end
