# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::Controllers::Menu::RssReadingMouseHandler do
  let(:menu_state_reader) do
    instance_double(Shoko::Adapters::Runtime::SessionState::MenuSnapshotProjectionAdapter,
                    rss_selection: nil, rss_context_menu: nil)
  end
  let(:menu_session_mutator) do
    instance_double(Shoko::Adapters::Runtime::SessionState::MenuSessionMutator, update_menu: nil)
  end
  let(:intent_handler) do
    instance_double(Shoko::Application::Ports::Inbound::MenuIntentHandler, handle_menu_intent: nil)
  end
  let(:screen) do
    instance_double(Shoko::Adapters::Ui::Components::Screens::RssReaderScreenComponent,
                    reading_pane_active?: true)
  end
  let(:bounds) { Shoko::Adapters::Ui::Components::Rect.new(x: 1, y: 1, width: 80, height: 24) }

  subject(:handler) do
    described_class.new(
      menu_state_reader: menu_state_reader, menu_session_mutator: menu_session_mutator,
      intent_handler: intent_handler, rss_reader_screen: screen
    )
  end

  # SGR button encodings: bit 5 is motion, bit 6 the wheel, low bits the button.
  def press(x: 10, y: 8) = { button: 0, released: false, x: x, y: y }
  def drag(x: 20, y: 8) = { button: 32, released: false, x: x, y: y }
  def release(x: 20, y: 8) = { button: 0, released: true, x: x, y: y }
  def right_press(x: 10, y: 8) = { button: 2, released: false, x: x, y: y }
  def wheel = { button: 64, released: false, x: 10, y: 8 }

  def selection(from = 4, to = 9) = { start_index: from, end_index: to, text: 'quote' }

  it 'declines every event when no article is open' do
    allow(screen).to receive(:reading_pane_active?).and_return(false)

    expect(handler.handle(press, bounds: bounds)).to be(false)
  end

  it 'declines a wheel turn so the pane can scroll' do
    allow(screen).to receive(:reading_hit).and_return(3)

    expect(handler.handle(wheel, bounds: bounds)).to be(false)
  end

  describe 'dragging out a selection' do
    before do
      allow(screen).to receive(:reading_hit).and_return(3)
      allow(screen).to receive(:reading_selection_from_points).and_return({ start_index: 3, end_index: 9 })
      allow(screen).to receive(:reading_selection_payload).and_return(selection(3, 9))
    end

    it 'clears any previous selection when a new drag begins' do
      handler.handle(press, bounds: bounds)

      expect(menu_session_mutator).to have_received(:update_menu)
        .with(hash_including(rss_selection: nil, rss_context_menu: nil))
    end

    it 'writes the selection as the pointer moves' do
      handler.handle(press, bounds: bounds)
      handler.handle(drag, bounds: bounds)

      expect(menu_session_mutator).to have_received(:update_menu)
        .with(hash_including(rss_selection: selection(3, 9)))
    end

    it 'stores the resolved text with the selection' do
      handler.handle(press, bounds: bounds)
      handler.handle(release, bounds: bounds)

      expect(menu_session_mutator).to have_received(:update_menu)
        .with(hash_including(rss_selection: hash_including(text: 'quote')))
    end

    it 'ignores a drag that never started' do
      expect(handler.handle(drag, bounds: bounds)).to be(false)
    end

    it 'ignores a release that never started' do
      expect(handler.handle(release, bounds: bounds)).to be(false)
    end
  end

  describe 'clicking off the prose' do
    it 'dismisses an existing selection' do
      allow(screen).to receive(:reading_hit).and_return(nil)
      allow(menu_state_reader).to receive(:rss_selection).and_return(selection)

      handler.handle(press, bounds: bounds)

      expect(menu_session_mutator).to have_received(:update_menu)
        .with(hash_including(rss_selection: nil, rss_context_menu: nil))
    end

    it 'does nothing when there was nothing selected' do
      allow(screen).to receive(:reading_hit).and_return(nil)

      expect(handler.handle(press, bounds: bounds)).to be(false)
    end
  end

  describe 'the actions menu' do
    before { allow(screen).to receive(:reading_hit).and_return(6) }

    it 'opens over an existing selection when right-clicked inside it' do
      allow(menu_state_reader).to receive(:rss_selection).and_return(selection(4, 9))

      handler.handle(right_press(x: 12, y: 7), bounds: bounds)

      expect(menu_session_mutator).to have_received(:update_menu).with(
        hash_including(rss_selection: selection(4, 9),
                       rss_context_menu: { anchor_column: 13, anchor_row: 8 })
      )
    end

    it 'converts parsed zero-based coordinates to the canvas coordinate system' do
      allow(menu_state_reader).to receive(:rss_selection).and_return(selection(4, 9))
      handler.handle(right_press(x: 12, y: 7), bounds: bounds)

      expect(screen).to have_received(:reading_hit).with(13, 8, bounds)
    end

    # Right-clicking a bare word should still give the actions something to act on.
    it 'selects the word under the pointer when right-clicked outside the selection' do
      allow(menu_state_reader).to receive(:rss_selection).and_return(selection(40, 45))
      allow(screen).to receive(:reading_word_at).and_return({ start_index: 4, end_index: 10 })
      allow(screen).to receive(:reading_selection_payload).and_return(selection(4, 10))

      handler.handle(right_press, bounds: bounds)

      expect(menu_session_mutator).to have_received(:update_menu)
        .with(hash_including(rss_selection: selection(4, 10)))
    end

    it 'dispatches the chosen action as an intent' do
      allow(menu_state_reader).to receive(:rss_context_menu).and_return({ anchor_column: 5, anchor_row: 5 })
      allow(screen).to receive(:context_menu_hit).and_return({ label: 'Look Up',
                                                               intent: :rss_reader_lookup_selection })

      handler.handle(release, bounds: bounds)

      expect(intent_handler).to have_received(:handle_menu_intent).with(:rss_reader_lookup_selection, nil)
    end

    it 'closes without acting when the click misses the card' do
      allow(menu_state_reader).to receive(:rss_context_menu).and_return({ anchor_column: 5, anchor_row: 5 })
      allow(screen).to receive(:context_menu_hit).and_return(nil)

      handler.handle(release, bounds: bounds)

      expect(intent_handler).not_to have_received(:handle_menu_intent)
      expect(menu_session_mutator).to have_received(:update_menu).with(hash_including(rss_context_menu: nil))
    end

    it 'swallows the press that precedes the acting release' do
      allow(menu_state_reader).to receive(:rss_context_menu).and_return({ anchor_column: 5, anchor_row: 5 })

      expect(handler.handle(press, bounds: bounds)).to eq(:handled)
      expect(intent_handler).not_to have_received(:handle_menu_intent)
    end
  end
end
