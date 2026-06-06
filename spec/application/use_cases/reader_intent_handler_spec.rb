# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::UseCases::ReaderIntentHandler do
  class ReaderIntentHandlerSpecReaderSessionStore
    include Shoko::Application::Ports::Outbound::ReaderSessionStore

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

  let(:navigation_service) { double('NavigationService').as_null_object }
  let(:bookmark_service) { double('BookmarkService').as_null_object }
  let(:reader_port_adapter) { double('ReaderPortAdapter').as_null_object }
  let(:reader_session_store) do
    ReaderIntentHandlerSpecReaderSessionStore.new(
      Shoko::Application::Ports::Outbound::State::ReaderSnapshot.build(current_chapter: 2)
    )
  end

  let(:reader_view_mutator) { double('ReaderViewMutator').as_null_object }
  let(:reader_view_state_store) do
    double('ReaderViewStateStore',
           load: Shoko::Application::Ports::Outbound::State::ReaderViewSnapshot.build)
  end
  let(:annotation_service) { double('AnnotationService').as_null_object }
  let(:app_config_store) do
    double('AppConfigStore', load: double(page_numbering_mode: :absolute, line_spacing: :normal))
  end
  let(:notification_writer) { double('NotificationWriter').as_null_object }

  subject(:handler) do
    described_class.new(
      navigation_service: navigation_service,
      bookmark_service: bookmark_service,
      reader_session_store: reader_session_store,
      reader_view_state_store: reader_view_state_store,
      reader_view_mutator: reader_view_mutator,
      app_config_store: app_config_store,
      notification_writer: notification_writer,
      reader_overlay_control: reader_port_adapter,
      reader_popup_control: reader_port_adapter,
      reader_dictionary_control: reader_port_adapter,
      reader_search_control: reader_port_adapter,
      reader_toc_control: reader_port_adapter,
      reader_annotation_editor_control: reader_port_adapter,
      reader_lifecycle_control: reader_port_adapter,
      application_exit_control: reader_port_adapter,
      annotation_service: annotation_service
    )
  end

  def payload_for(intent)
    case intent
    when :edit_annotation_text, :edit_reader_dictionary_query, :edit_in_book_search, :edit_toc_filter
      Shoko::Application::UseCases::Requests::EditOp.new(operation: :insert, text: 'x')
    when :sidebar_move_up, :popup_move_up, :dictionary_move_up, :search_move_up, :toc_move_up
      Shoko::Application::UseCases::Requests::SelectionDelta.new(delta: -1)
    when :sidebar_move_down, :popup_move_down, :dictionary_move_down, :search_move_down, :toc_move_down
      Shoko::Application::UseCases::Requests::SelectionDelta.new(delta: 1)
    when :move_annotation_cursor
      Shoko::Application::UseCases::Requests::CursorMove.new(direction: :left)
    end
  end

  it 'accepts every declared reader intent' do
    Shoko::Application::Ports::Inbound::ReaderIntentHandler::INTENT_SYMBOLS.each do |intent|
      expect { handler.handle_reader_intent(intent, payload_for(intent)) }.not_to raise_error
    end
  end

  it 'fails fast on unknown reader intents' do
    expect { handler.handle_reader_intent(:totally_unknown) }.to raise_error(ArgumentError, /unsupported reader intent/)
  end

  it 'fails fast on invalid payload classes' do
    expect do
      handler.handle_reader_intent(:edit_reader_dictionary_query, Object.new)
    end.to raise_error(ArgumentError, /invalid payload/)
  end
end
