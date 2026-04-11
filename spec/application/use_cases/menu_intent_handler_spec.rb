# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::UseCases::MenuIntentHandler do
  class MenuIntentHandlerSpecMenuSessionStore
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
  end

  class MenuIntentHandlerSpecMenuTransientStore
    include Shoko::Core::Ports::Outbound::MenuTransientStore

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
    MenuIntentHandlerSpecMenuSessionStore.new(
      Shoko::Core::Models::Session::MenuSessionSnapshot.build(
        selected: 0,
        browse_selected: 0,
        settings_selected: 0,
        search_query: '',
        search_cursor: 0,
        library_details_open: false,
        dictionary_query: '',
        dictionary_cursor: 0,
        dictionary_selected: 0,
        mode: :menu,
        download_query: '',
        download_cursor: 0,
        download_selected: 0,
        wipe_cache_cached: true,
        wipe_cache_downloads: false,
        wipe_cache_nuke: false,
        wipe_cache_annotations: false,
        wipe_cache_bookmarks: false,
        wipe_cache_progress: false,
        wipe_cache_config: false
      )
    )
  end
  let(:menu_transient_store) do
    MenuIntentHandlerSpecMenuTransientStore.new(Shoko::Core::Models::Session::MenuTransientSnapshot.build)
  end
  let(:menu_port_adapter) do
    double(
      'MenuActionPortAdapter',
      selected_annotation_context: nil,
      browse_item_count: 0,
      library_item_count: 0,
      selected_library_path: nil,
      selected_download_result: nil
    ).as_null_object
  end
  let(:state_controller) { double('MenuStateController').as_null_object }
  let(:app_config_store) do
    double(
      'AppConfigStore',
      load: Shoko::Core::Models::Session::ConfigSnapshot.build(download_source: :gutendex)
    )
  end
  let(:settings_service) { double('SettingsService').as_null_object }
  let(:annotation_service) { double('AnnotationService', list_all: {}).as_null_object }
  let(:catalog) { double('Catalog').as_null_object }

  subject(:handler) do
    described_class.new(
      menu_session_store: menu_session_store,
      app_config_store: app_config_store,
      menu_mode_control: menu_port_adapter,
      menu_browse_inspection: menu_port_adapter,
      menu_download_selection: menu_port_adapter,
      menu_annotation_control: menu_port_adapter,
      application_exit_control: menu_port_adapter,
      reader_launch_service: state_controller,
      download_workflow: state_controller,
      dictionary_workflow: state_controller,
      translator_workflow: state_controller,
      rss_reader_workflow: state_controller,
      annotation_workflow: state_controller,
      settings_service: settings_service,
      annotation_service: annotation_service,
      catalog: catalog,
      menu_transient_store: menu_transient_store
    )
  end

  def payload_for(intent)
    case intent
    when :browse_insert_text, :dictionary_query_insert_text, :download_query_insert_text,
         :rss_reader_add_feed_insert_text, :rss_reader_filter_insert_text,
         :annotation_editor_insert_text, :translator_input_insert_text
      Shoko::Application::UseCases::Requests::TextInput.new(text: 'x')
    when :move_menu_selection_up, :move_browse_selection_up, :move_library_selection_up,
         :move_settings_selection_up, :move_dictionary_selection_up, :move_download_selection_up,
         :move_annotation_selection_up, :move_translator_language_selection_up, :rss_reader_move_up
      Shoko::Application::UseCases::Requests::SelectionDelta.new(delta: -1)
    when :move_menu_selection_down, :move_browse_selection_down, :move_library_selection_down,
         :move_settings_selection_down, :move_dictionary_selection_down, :move_download_selection_down,
         :move_download_source_selection_down, :move_annotation_selection_down,
         :move_translator_language_selection_down, :rss_reader_move_down
      Shoko::Application::UseCases::Requests::SelectionDelta.new(delta: 1)
    when :move_download_source_selection_up
      Shoko::Application::UseCases::Requests::SelectionDelta.new(delta: -1)
    when :annotation_editor_move_left
      Shoko::Application::UseCases::Requests::CursorMove.new(direction: :left)
    when :annotation_editor_move_right
      Shoko::Application::UseCases::Requests::CursorMove.new(direction: :right)
    when :annotation_editor_move_up
      Shoko::Application::UseCases::Requests::CursorMove.new(direction: :up)
    when :annotation_editor_move_down
      Shoko::Application::UseCases::Requests::CursorMove.new(direction: :down)
    when :open_dictionary_mode
      Shoko::Application::UseCases::Requests::ModeChange.new(mode: :dictionary)
    when :close_dictionary_mode
      Shoko::Application::UseCases::Requests::ModeChange.new(mode: :settings)
    when :open_download_mode
      Shoko::Application::UseCases::Requests::ModeChange.new(mode: :download)
    when :close_download_mode
      Shoko::Application::UseCases::Requests::ModeChange.new(mode: :menu)
    when :close_download_source_mode
      Shoko::Application::UseCases::Requests::ModeChange.new(mode: :download)
    when :close_rss_reader_mode
      Shoko::Application::UseCases::Requests::ModeChange.new(mode: :rss_reader)
    end
  end

  it 'accepts every declared menu intent' do
    Shoko::Core::Ports::Inbound::MenuIntentHandler::INTENT_SYMBOLS.each do |intent|
      expect { handler.handle_menu_intent(intent, payload_for(intent)) }.not_to raise_error
    end
  end

  it 'fails fast on unknown menu intents' do
    expect { handler.handle_menu_intent(:totally_unknown) }.to raise_error(ArgumentError, /unsupported menu intent/)
  end

  it 'fails fast on invalid payload classes' do
    expect do
      handler.handle_menu_intent(:browse_insert_text, Object.new)
    end.to raise_error(ArgumentError, /invalid payload/)
  end
end
