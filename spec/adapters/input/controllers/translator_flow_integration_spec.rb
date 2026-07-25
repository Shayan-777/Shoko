# frozen_string_literal: true

require 'spec_helper'

# End-to-end flow for the in-book translator: the controller drives the real UI
# session, which writes through the real reader session mutator into the real
# state stores; the popup component then re-renders from that state. Only the
# translation backend is faked. This proves the translator_* view fields, the
# live popup registry entry, and the :translator mode all round-trip for real.
RSpec.describe 'Translator end-to-end flow' do
  let(:terminal_capabilities) { Shoko::Adapters::Output::Terminal::NullTerminalCapabilities.new }
  let(:null_logger) { Shoko::Core::Services::NullLogger.new }
  let(:config_dir) { @tmpdir }
  let(:config_storage) { SpecSupport::FakeConfigStorage.new(config_dir) }

  around do |example|
    Dir.mktmpdir do |dir|
      @tmpdir = dir
      with_env('XDG_CONFIG_HOME' => dir) { example.run }
    end
  end

  let(:schema_registry) do
    Shoko::Application::State::SchemaRegistry.new
      .register(Shoko::Core::Reading::Schema)
      .register(Shoko::Application::State::Schema::ReaderProcess)
      .register(Shoko::Application::State::Schema::ReaderPagination)
      .register(Shoko::Application::State::Schema::ReaderView)
      .register(Shoko::Application::State::Schema::MenuProcess)
      .register(Shoko::Application::State::Schema::MenuTransient)
      .register(Shoko::Application::State::Schema::Config)
      .register(Shoko::Application::State::Schema::UiGlobals)
  end
  let(:state_store) do
    Shoko::Application::State::StateStore.new(
      config_storage: config_storage,
      terminal_capabilities: terminal_capabilities, schema_registry: schema_registry
    )
  end
  let(:reader_session_store) { Shoko::Adapters::Runtime::SessionState::ReaderSessionStoreAdapter.new(state_store) }
  let(:reader_view_state_store) { Shoko::Adapters::Runtime::SessionState::ReaderViewStateStoreAdapter.new(state_store) }
  let(:reader_pagination_store) { Shoko::Adapters::Runtime::SessionState::ReaderPaginationStoreAdapter.new(state_store) }
  let(:app_config_store) { Shoko::Adapters::Runtime::SessionState::AppConfigStoreAdapter.new(state_store) }
  let(:component_registry) { Shoko::Adapters::Ui::State::ReaderComponentRegistry.new }
  let(:reader_state_reader) do
    Shoko::Adapters::Runtime::SessionState::ReaderSnapshotProjectionAdapter.new(
      state: state_store, reader_session_store: reader_session_store,
      reader_view_state_store: reader_view_state_store, reader_pagination_store: reader_pagination_store,
      component_registry: component_registry
    )
  end
  let(:reader_session_mutator) do
    Shoko::Adapters::Runtime::SessionState::ReaderSessionMutator.new(
      reader_session_store: reader_session_store, reader_view_state_store: reader_view_state_store,
      reader_pagination_store: reader_pagination_store, app_config_store: app_config_store,
      component_registry: component_registry
    )
  end
  let(:component_factory) { Shoko::Adapters::Ui::ComponentFactory.new }
  let(:translator_ui_session) do
    Shoko::Adapters::Ui::Sessions::TranslatorUiSessionAdapter.new(
      reader_state_reader: reader_state_reader, reader_session_mutator: reader_session_mutator,
      ui_component_factory: component_factory, logger: null_logger
    )
  end

  # A fake LibreTranslate that echoes a fixed translation for the chosen target.
  let(:translation_service) do
    Class.new do
      def translate(text, source_lang:, target_lang:)
        Shoko::Core::Models::TranslationResult.new(
          query: text, translated_text: "[#{target_lang}] #{text}",
          source_lang: source_lang, target_lang: target_lang, detected_source_lang: 'en'
        )
      end
    end.new
  end
  let(:input_controller) { instance_double(Shoko::Adapters::Input::ReaderInputController, enter_modal_mode: nil, exit_modal_mode: nil) }
  let(:notification_service) { instance_double(Shoko::Adapters::Output::NotificationService, set_message: nil) }

  subject(:controller) do
    Shoko::Adapters::Input::Controllers::TranslatorController.new(
      reader_state: reader_state_reader, reader_session_mutator: reader_session_mutator,
      translation_service: translation_service, translator_ui_session: translator_ui_session,
      input_controller: input_controller, notification_service: notification_service,
      async_relay: Shoko::Application::Services::AsyncResultRelay.new, logger: null_logger
    )
  end

  def insert(char)
    controller.edit_translator(Shoko::Application::UseCases::Requests::EditOp.new(operation: :insert, text: char))
  end

  def strip_ansi(text)
    text.to_s.gsub(%r{\e\[[0-9;]*[ -/]*[@-~]}, '')
  end

  let(:terminal) { Shoko::TestSupport::TerminalDouble }
  let(:surface) { Shoko::Adapters::Ui::Components::Surface.new(terminal) }
  let(:bounds) { Shoko::Adapters::Ui::Components::Rect.new(x: 1, y: 1, width: 100, height: 20) }

  def render_text
    terminal.reset!
    reader_state_reader.translator_lookup_popup.render(surface, bounds)
    terminal.writes.group_by { |w| w[:row] }.values.map { |ws| strip_ansi(ws.map { |w| w[:text] }.join) }.join("\n")
  end

  it 'opens, translates, switches target language via the picker, and re-translates — all from real state' do
    expect(controller.open_translator).to eq(:handled)
    expect(reader_session_store.load.mode).to eq(:translator)
    expect(reader_state_reader.translator_lookup_popup).to be_a(
      Shoko::Adapters::Ui::Components::TranslatorLookupPopupComponent
    )
    expect(reader_state_reader.translator_languages).not_to be_empty

    'hello'.each_char { |c| insert(c) }
    expect(reader_state_reader.translator_query).to eq('hello')

    controller.translator_confirm
    expect(reader_state_reader.translator_result.translated_text).to eq('[en] hello')
    expect(render_text).to include('[en] hello')

    # Open the language picker (Target), filter to German, and pick it.
    controller.translator_cycle_picker
    expect(reader_state_reader.translator_picker_side).to eq(:target)
    'german'.each_char { |c| insert(c) }
    expect(reader_state_reader.translator_picker_query).to eq('german')

    controller.translator_confirm
    expect(reader_state_reader.translator_picker_side).to be_nil
    expect(reader_state_reader.translator_target_lang).to eq('de')
    # Picking the language re-translates in place against the new target.
    expect(reader_state_reader.translator_result.translated_text).to eq('[de] hello')
    expect(render_text).to include('[de] hello')

    controller.close_translator
    expect(reader_session_store.load.mode).to eq(:read)
    expect(reader_state_reader.translator_lookup_popup).to be_nil
  end

  it 'swaps the language pair and re-translates' do
    controller.open_translator
    'hi'.each_char { |c| insert(c) }
    controller.translator_confirm # auto -> en

    controller.translator_swap_languages
    # auto source resolves to the detected language (en); old target (en) becomes source.
    expect(reader_state_reader.translator_source_lang).to eq('en')
    expect(reader_state_reader.translator_target_lang).to eq('de')
    expect(reader_state_reader.translator_result.translated_text).to eq('[de] hi')
  end
end
