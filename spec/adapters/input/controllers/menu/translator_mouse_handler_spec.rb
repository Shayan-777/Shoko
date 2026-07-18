# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::Controllers::Menu::TranslatorMouseHandler do
  let(:bounds) { Shoko::Adapters::Ui::Components::Rect.new(x: 1, y: 1, width: 120, height: 30) }
  let(:menu_state_class) do
    Struct.new(
      :mode,
      :translator_focus,
      :translator_status,
      :translator_input_text,
      :translator_input_cursor,
      :translator_output_text,
      :translator_message,
      :translator_detected_source_lang,
      :translator_dropdown_selected,
      :translator_source_lang,
      :translator_target_lang,
      :translator_languages,
      :translator_selection,
      :translator_context_menu
    )
  end
  let(:menu_mutator_class) do
    Class.new do
      def initialize(state)
        @state = state
      end

      def update_menu(payload)
        payload.each do |key, value|
          @state.public_send("#{key}=", value)
        end
      end
    end
  end
  let(:menu_state) do
    menu_state_class.new(
      :translator,
      :input,
      :done,
      'Hallo Welt',
      5,
      'Hello world',
      'Translated de -> en',
      'de',
      0,
      'auto',
      'en',
      [
        { code: 'en', name: 'English' },
        { code: 'de', name: 'German' },
      ],
      nil,
      nil
    )
  end
  let(:translator_screen) do
    Shoko::Adapters::Ui::Components::Screens::TranslatorScreenComponent.new(menu_state_reader: menu_state)
  end
  let(:menu_session_mutator) { menu_mutator_class.new(menu_state) }
  let(:input_controller) { instance_double(Shoko::Adapters::Input::Controllers::Menu::InputController, activate: nil) }
  let(:notification_service) { instance_double(Shoko::Adapters::Output::NotificationService, set_message: nil) }
  let(:clipboard_service) do
    instance_double(Shoko::Adapters::Output::Clipboard::ClipboardService, available?: true, read_available?: true)
  end

  subject(:support) do
    described_class.new(
      menu_state_reader: menu_state,
      menu_session_mutator: menu_session_mutator,
      input_controller: input_controller,
      translator_screen: translator_screen,
      clipboard_service: clipboard_service,
      notification_service: notification_service
    )
  end

  def mouse_event(column:, row:, button:, released:)
    {
      x: column - 1,
      y: row - 1,
      button: button,
      released: released,
    }
  end

  def source_drag_columns
    layout = translator_screen.send(:layout_metrics, bounds)
    box = layout[:left_box]
    [box.col + 2, translator_screen.send(:body_start_row, box, :source), box.col + 7]
  end

  def target_drag_columns
    layout = translator_screen.send(:layout_metrics, bounds)
    box = layout[:right_box]
    [box.col + 2, translator_screen.send(:body_start_row, box, :target), box.col + 7]
  end

  it 'copies selected translator output text through the right-click popup' do
    start_column, row, end_column = target_drag_columns
    allow(clipboard_service).to receive(:copy_with_feedback) do |text, &block|
      expect(text).to eq('Hello')
      block&.call('Copied to clipboard!')
      true
    end

    expect(support.handle(mouse_event(column: start_column, row: row, button: 0, released: false), bounds: bounds)).to be_truthy
    expect(support.handle(mouse_event(column: end_column, row: row, button: 32, released: false), bounds: bounds)).to be_truthy
    expect(support.handle(mouse_event(column: end_column, row: row, button: 0, released: true), bounds: bounds)).to be_truthy

    expect(menu_state.translator_selection).to eq(pane: :target, start_index: 0, end_index: 5)

    expect(support.handle(mouse_event(column: start_column + 1, row: row, button: 2, released: false), bounds: bounds)).to be_truthy

    popup_box = translator_screen.context_menu_popup_box(bounds)
    support.handle(mouse_event(column: popup_box.col + 2, row: popup_box.row + 1, button: 0, released: true), bounds: bounds)

    expect(clipboard_service).to have_received(:copy_with_feedback).with('Hello')
    expect(notification_service).to have_received(:set_message).with('Copied to clipboard!')
    expect(menu_state.translator_context_menu).to be_nil
  end

  it 'pastes clipboard text into the source pane by replacing the current source selection' do
    start_column, row, end_column = source_drag_columns
    allow(clipboard_service).to receive(:read_with_feedback) do |&block|
      block&.call('Pasted from clipboard')
      'Salut'
    end

    support.handle(mouse_event(column: start_column, row: row, button: 0, released: false), bounds: bounds)
    support.handle(mouse_event(column: end_column, row: row, button: 32, released: false), bounds: bounds)
    support.handle(mouse_event(column: end_column, row: row, button: 0, released: true), bounds: bounds)

    expect(menu_state.translator_selection).to eq(pane: :source, start_index: 0, end_index: 5)

    support.handle(mouse_event(column: start_column + 1, row: row, button: 2, released: false), bounds: bounds)

    popup_box = translator_screen.context_menu_popup_box(bounds)
    support.handle(mouse_event(column: popup_box.col + 2, row: popup_box.row + 2, button: 0, released: true), bounds: bounds)

    expect(menu_state.translator_input_text).to eq('Salut Welt')
    expect(menu_state.translator_input_cursor).to eq(5)
    expect(menu_state.translator_selection).to be_nil
    expect(menu_state.translator_context_menu).to be_nil
    expect(notification_service).to have_received(:set_message).with('Pasted from clipboard')
  end
end
