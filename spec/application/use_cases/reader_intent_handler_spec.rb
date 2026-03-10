# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::UseCases::ReaderIntentHandler do
  let(:navigation_service) { double('NavigationService').as_null_object }
  let(:bookmark_service) { double('BookmarkService').as_null_object }
  let(:reader_runtime) { double('ReaderIntentRuntime', sidebar_visible?: false, sidebar_toc_tab?: false).as_null_object }
  let(:reader_state_reader) { double('ReaderStateReader', current_chapter: 2).as_null_object }

  subject(:handler) do
    described_class.new(
      navigation_service: navigation_service,
      bookmark_service: bookmark_service,
      reader_state_reader: reader_state_reader,
      reader_runtime: reader_runtime
    )
  end

  def payload_for(intent)
    case intent
    when :dictionary_insert_text, :search_insert_text, :annotation_editor_insert_text
      Shoko::Application::UseCases::Requests::TextInput.new(text: 'x')
    when :sidebar_move_up, :popup_move_up, :dictionary_move_up, :search_move_up
      Shoko::Application::UseCases::Requests::SelectionDelta.new(delta: -1)
    when :sidebar_move_down, :popup_move_down, :dictionary_move_down, :search_move_down
      Shoko::Application::UseCases::Requests::SelectionDelta.new(delta: 1)
    when :annotation_editor_move_left
      Shoko::Application::UseCases::Requests::CursorMove.new(direction: :left)
    when :annotation_editor_move_right
      Shoko::Application::UseCases::Requests::CursorMove.new(direction: :right)
    when :annotation_editor_move_up
      Shoko::Application::UseCases::Requests::CursorMove.new(direction: :up)
    when :annotation_editor_move_down
      Shoko::Application::UseCases::Requests::CursorMove.new(direction: :down)
    end
  end

  it 'accepts every declared reader intent' do
    Shoko::Core::Ports::Inbound::ReaderIntentHandler::INTENT_SYMBOLS.each do |intent|
      expect { handler.handle_reader_intent(intent, payload_for(intent)) }.not_to raise_error
    end
  end

  it 'fails fast on unknown reader intents' do
    expect { handler.handle_reader_intent(:totally_unknown) }.to raise_error(ArgumentError, /unsupported reader intent/)
  end

  it 'fails fast on invalid payload classes' do
    expect do
      handler.handle_reader_intent(:dictionary_insert_text, Object.new)
    end.to raise_error(ArgumentError, /invalid payload/)
  end
end
