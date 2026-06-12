# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::Controllers::UIController do
  let(:dictionary_controller) { instance_double('DictionaryController', close_dictionary: nil, refresh_theme: nil) }
  let(:annotation_controller) { instance_double('AnnotationOverlayController', refresh_theme: nil) }
  let(:in_book_search_controller) { instance_double('InBookSearchController', refresh_theme: nil) }
  let(:toc_controller) { instance_double('TocLookupController', refresh_theme: nil) }
  let(:translator_controller) { instance_double('TranslatorController', refresh_theme: nil) }
  let(:notes_controller) { instance_double('NotesLookupController', refresh_theme: nil) }
  let(:input_controller) { instance_double('ReaderInputController') }
  let(:reader_state) do
    instance_double('ReaderStateReader',
                    current_chapter: 0, bookmarks: [], annotations: [],
                    selection: nil, annotations_overlay_selected: 0,
                    mode: :read, running?: true, message: nil, popup_menu: nil,
                    annotations_overlay: nil, annotation_editor_overlay: nil,
                    dictionary_popup: nil, dictionary_panel: nil)
  end
  let(:config_reader) do
    instance_double('ConfigReader', theme: :dark, view_mode: :single,
                                    line_spacing: :normal, page_numbering_mode: :dynamic,
                                    show_page_numbers: true)
  end
  let(:reader_session_mutator) do
    instance_double('ReaderSessionMutator', update_reader: nil, update_config: nil,
                                            clear_selection: nil,
                                            toggle_view_mode: nil)
  end
  let(:ui_state) do
    instance_double('UIStateReader', terminal_width: 80, terminal_height: 24)
  end
  let(:notification_service) { instance_double('NotificationService', set_message: nil) }
  let(:theme_context) { Struct.new(:theme_id, :color_mode).new(:sepia, :light) }
  let(:ui_component_factory) { instance_double('UIComponentFactory', apply_theme: theme_context) }

  def build_controller
    described_class.new(
      deps: described_class::Dependencies.build(
        reader_state: reader_state,
        config_reader: config_reader,
        reader_session_mutator: reader_session_mutator,
        ui_state: ui_state,
        dictionary_controller: dictionary_controller,
        annotation_controller: annotation_controller,
        in_book_search_controller: in_book_search_controller,
        toc_controller: toc_controller,
        translator_controller: translator_controller,
        notes_controller: notes_controller,
        input_controller: input_controller,
        reader_controller: nil,
        notification_service: notification_service,
        selection_service: nil,
        rendered_content_reader: nil,
        clipboard_service: nil,
        ui_component_factory: ui_component_factory,
        annotation_service: nil,
        logger: nil
      )
    )
  end

  it 'allows close_dictionary to be called with a key argument' do
    controller = build_controller
    expect(dictionary_controller).to receive(:close_dictionary_lookup)

    controller.close_dictionary('q')
  end

  it 'propagates resolved theme context to active UI controllers' do
    controller = build_controller

    context = controller.refresh_theme(theme: :sepia)

    expect(context.theme_id).to eq(:sepia)
    expect(ui_component_factory).to have_received(:apply_theme).with(theme_id: :sepia)
    expect(dictionary_controller).to have_received(:refresh_theme).with(theme_context: context)
    expect(annotation_controller).to have_received(:refresh_theme).with(theme_context: context)
    expect(in_book_search_controller).to have_received(:refresh_theme).with(theme_context: context)
    expect(toc_controller).to have_received(:refresh_theme).with(theme_context: context)
    expect(translator_controller).to have_received(:refresh_theme).with(theme_context: context)
  end

  it 'delegates view-mode toggle through reader session mutator' do
    controller = build_controller

    controller.toggle_view_mode

    expect(reader_session_mutator).to have_received(:toggle_view_mode)
  end

  it 'updates config and invalidates width when increasing line spacing' do
    controller = build_controller

    controller.increase_line_spacing

    expect(reader_session_mutator).to have_received(:update_config).with(line_spacing: :relaxed)
    expect(reader_session_mutator).to have_received(:update_reader).with(last_width: 0)
  end

  it 'routes the popup Translate action into the bar-anchored translator' do
    allow(input_controller).to receive(:dispatch_reader_intent)
    controller = build_controller
    action = { action: :translate, data: { selection_range: { start: 0, end: 4 } } }

    controller.handle_popup_action(action)

    expect(input_controller).to have_received(:dispatch_reader_intent).with(:open_translator, action)
  end
end
