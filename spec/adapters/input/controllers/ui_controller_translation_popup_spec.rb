# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::Controllers::UIController do
  FakeReaderState = Struct.new(:selection, :translation_popup, keyword_init: true)

  class TranslationPopupSpecMutator
    attr_reader :state, :updates, :cleared

    def initialize(state)
      @state = state
      @updates = []
      @cleared = 0
    end

    def update_reader(attributes)
      @updates << attributes
      @state.translation_popup = attributes[:translation_popup] if attributes.key?(:translation_popup)
    end

    def clear_selection
      @cleared += 1
    end

    def update_config(*); end

    def update_sidebar(*); end

    def toggle_view_mode; end
  end

  let(:selection_range) do
    {
      start: { page_id: 0, geometry_key: 'g1', line_offset: 0, cell_index: 0, row: 1, column_origin: 1 },
      end: { page_id: 0, geometry_key: 'g1', line_offset: 0, cell_index: 4, row: 1, column_origin: 1 }
    }
  end
  let(:reader_state) { FakeReaderState.new(selection: selection_range, translation_popup: nil) }
  let(:reader_session_mutator) { TranslationPopupSpecMutator.new(reader_state) }
  let(:config_reader) do
    instance_double(
      'ConfigReader',
      theme: :dark,
      view_mode: :single,
      line_spacing: :normal,
      page_numbering_mode: :dynamic,
      show_page_numbers: true
    )
  end
  let(:sidebar_state) { instance_double('SidebarStateReader', sidebar_visible?: false, sidebar_active_tab: :toc) }
  let(:ui_state) { instance_double('UIStateReader', terminal_width: 80, terminal_height: 24) }
  let(:selection_service) { instance_double('SelectionService', extract_text: 'Hallo Welt') }
  let(:rendered_content_reader) { instance_double('RenderedContentReader', rendered_lines: {}) }
  let(:notification_service) { instance_double('NotificationService', set_message: nil) }
  let(:translation_service) do
    instance_double(
      'TranslationService',
      translate: Shoko::Core::Models::TranslationResult.new(
        query: 'Hallo Welt',
        translated_text: 'Hello world',
        source_lang: 'auto',
        target_lang: 'en',
        detected_source_lang: 'de'
      )
    )
  end
  let(:translation_popup) { Shoko::Adapters::Ui::Components::TranslationPopupComponent.new }
  let(:ui_component_factory) { instance_double('UIComponentFactory', translation_popup: translation_popup, apply_theme: nil) }

  subject(:controller) do
    described_class.new(
      deps: described_class::Dependencies.build(
        reader_state: reader_state,
        config_reader: config_reader,
        reader_session_mutator: reader_session_mutator,
        sidebar_state: sidebar_state,
        ui_state: ui_state,
        selection_service: selection_service,
        rendered_content_reader: rendered_content_reader,
        sidebar_controller: instance_double('SidebarController'),
        dictionary_controller: instance_double('DictionaryController', refresh_theme: nil),
        annotation_controller: instance_double('AnnotationController', refresh_theme: nil),
        in_book_search_controller: instance_double('SearchController', refresh_theme: nil),
        input_controller: instance_double('ReaderInputController'),
        reader_controller: nil,
        notification_service: notification_service,
        clipboard_service: nil,
        ui_component_factory: ui_component_factory,
        annotation_service: nil,
        translation_service: translation_service,
        logger: nil
      )
    )
  end

  it 'opens a translation popup for the selected text' do
    controller.handle_popup_action(action: :translate, data: { selection_range: selection_range })

    expect(translation_service).to have_received(:translate).with('Hallo Welt', source_lang: 'auto', target_lang: 'en')
    expect(reader_state.translation_popup).to equal(translation_popup)
    expect(translation_popup).to be_visible
  end

  it 'closes the translation popup on cancel input' do
    translation_popup.show(
      Shoko::Core::Models::TranslationResult.new(
        query: 'Hallo Welt',
        translated_text: 'Hello world',
        source_lang: 'auto',
        target_lang: 'en',
        detected_source_lang: 'de'
      )
    )
    reader_state.translation_popup = translation_popup

    controller.handle_translation_popup_input(["\e"])

    expect(reader_state.translation_popup).to be_nil
    expect(reader_session_mutator.cleared).to eq(1)
  end
end
