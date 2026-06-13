# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::Controllers::MouseableReader do
  describe '#spurious_post_mouse_key?' do
    let(:reader) { described_class.allocate }

    it "does not drop 'q' after mouse tokens" do
      ctx = { saw_mouse: true, saw_prefix: false }

      expect(reader.send(:spurious_post_mouse_key?, 'q', ctx)).to be(false)
    end

    it 'drops escape after mouse tokens' do
      ctx = { saw_mouse: false, saw_prefix: true }

      expect(reader.send(:spurious_post_mouse_key?, "\e", ctx)).to be(true)
    end
  end

  describe '#filter_mouse_sequences' do
    let(:reader) { described_class.allocate }

    before do
      reader.instance_variable_set(:@mouse_handler, Shoko::Adapters::Input::Annotations::MouseHandler.new)
    end

    it "does not trap 'q' behind a stale mouse prefix buffer" do
      reader.instance_variable_set(:@mouse_input_buffer, +"\e[")

      filtered = reader.send(:filter_mouse_sequences, ['q'])

      expect(filtered).to eq(['q'])
    end
  end

  describe '#handle_overlay_click' do
    let(:reader) { described_class.allocate }

    it 'handles popup context trigger on mouse press events before release gate' do
      event = { button: 2, released: false, x: 10, y: 5 }
      allow(reader).to receive(:popup_menu_active?).and_return(false)
      expect(reader).to receive(:popup_context_click_handled?).with(event).and_return(true)

      expect(reader.send(:handle_overlay_click, event)).to be(true)
    end

    it 'consumes the first release after context popup open' do
      event = { button: 2, released: true, x: 10, y: 5 }
      reader.instance_variable_set(:@suppress_popup_release_once, true)
      allow(reader).to receive(:popup_menu_active?).and_return(true)
      expect(reader).not_to receive(:handle_popup_click)

      expect(reader.send(:handle_overlay_click, event)).to be(true)
      expect(reader.instance_variable_get(:@suppress_popup_release_once)).to be(false)
    end
  end

  describe '#handle_content_mouse_event' do
    let(:reader) { described_class.allocate }
    let(:event) { { button: 0, released: true, x: 10, y: 5 } }

    it 'prioritizes inline link navigation before selection handling' do
      mouse_handler = instance_double(
        'MouseHandler',
        selecting: true,
        selection_start: { x: 10, y: 5 },
        selection_end: { x: 10, y: 5 },
        reset: nil
      )
      reader_session_mutator = instance_double('ReaderSessionMutator', update_reader: nil, clear_selection: nil)
      navigator = instance_double('InlineLinkNavigator', navigate: true, link_hit_for_event: nil)

      reader.instance_variable_set(:@mouse_handler, mouse_handler)
      reader.instance_variable_set(:@reader_session_mutator, reader_session_mutator)
      reader.instance_variable_set(:@inline_link_navigator, navigator)
      allow(reader).to receive(:dictionary_popup_visible?).and_return(false)
      allow(reader).to receive(:in_book_search_popup_visible?).and_return(false)

      expect(mouse_handler).not_to receive(:handle_event)
      expect(reader).to receive(:draw_screen).once

      reader.send(:handle_content_mouse_event, event)
    end
  end

  describe '#sync_inline_link_hover' do
    let(:reader) { described_class.allocate }
    let(:reader_state_reader) { instance_double('ReaderStateReader', current_chapter: 3, hovered_inline_link: nil) }
    let(:reader_session_mutator) { instance_double('ReaderSessionMutator', update_reader: nil) }
    let(:navigator) { instance_double('InlineLinkNavigator') }

    before do
      reader.instance_variable_set(:@inline_link_navigator, navigator)
      reader.instance_variable_set(:@reader_state_reader, reader_state_reader)
      reader.instance_variable_set(:@reader_session_mutator, reader_session_mutator)
    end

    it 'stores hover payload when pointer is over an inline link' do
      allow(navigator).to receive(:link_hit_for_event).and_return(
        href: '#note22',
        line_offset: 85,
        start_char: 3,
        end_char: 5
      )
      expect(reader_session_mutator).to receive(:update_reader).with(
        hovered_inline_link: {
          chapter_index: 3,
          line_offset: 85,
          start_char: 3,
          end_char: 5,
          href: '#note22',
        }
      )

      changed = reader.send(:sync_inline_link_hover, button: 35, released: false, x: 10, y: 5)

      expect(changed).to be_truthy
    end

    it 'clears hover payload when pointer moves off links' do
      allow(reader_state_reader).to receive(:hovered_inline_link).and_return(
        chapter_index: 3,
        line_offset: 85,
        start_char: 3,
        end_char: 5,
        href: '#note22'
      )
      allow(navigator).to receive(:link_hit_for_event).and_return(nil)
      expect(reader_session_mutator).to receive(:update_reader).with(hovered_inline_link: nil)

      changed = reader.send(:sync_inline_link_hover, button: 35, released: false, x: 1, y: 1)

      expect(changed).to be_truthy
    end
  end

  describe '#build_inline_link_navigator' do
    let(:reader) { described_class.allocate }
    let(:ui_state_reader) { instance_double('UiStateReader') }
    let(:reader_state_reader) { instance_double('ReaderStateReader') }
    let(:config_reader) { instance_double('ConfigReader') }
    let(:coordinate_service) { instance_double('CoordinateService') }
    let(:rendered_content_reader) { instance_double('RenderedContentReader') }
    let(:formatting_service) { instance_double('FormattingService') }
    let(:layout_service) { instance_double('LayoutService') }
    let(:state_controller) { instance_double('StateController') }
    let(:document) { instance_double('Document') }
    let(:deps) do
      instance_double(
        'MouseableReaderDependencies',
        ui_state_reader: ui_state_reader,
        formatting_service: formatting_service,
        layout_service: layout_service
      )
    end

    before do
      reader.instance_variable_set(:@reader_state_reader, reader_state_reader)
      reader.instance_variable_set(:@config_reader, config_reader)
      reader.instance_variable_set(:@coordinate_service, coordinate_service)
      reader.instance_variable_set(:@rendered_content_reader, rendered_content_reader)
      reader.instance_variable_set(:@logger_ref, nil)
      allow(reader).to receive(:doc).and_return(document)
      allow(reader).to receive(:state_controller).and_return(state_controller)
    end

    it 'passes ui state reader from dependencies to anchor resolver' do
      anchor_resolver = instance_double('AnchorResolver')
      navigator = instance_double('InlineLinkNavigator')

      expect(Shoko::Adapters::Input::Controllers::Reader::TocAnchorResolver).to receive(:new).with(
        hash_including(
          ui_state_reader: ui_state_reader,
          formatting_service: formatting_service,
          layout_service: layout_service,
          config_reader: config_reader
        )
      ).and_return(anchor_resolver)

      expect(Shoko::Adapters::Input::Controllers::Reader::InlineLinkNavigator).to receive(:new).with(
        hash_including(
          coordinate_service: coordinate_service,
          rendered_content_reader: rendered_content_reader,
          reader_state_reader: reader_state_reader,
          state_controller: state_controller,
          anchor_resolver: anchor_resolver
        )
      ).and_return(navigator)

      result = reader.send(:build_inline_link_navigator, deps)

      expect(result).to eq(navigator)
    end
  end
end

RSpec.describe Shoko::Adapters::Input::Controllers::MouseableReader, 'bar overlay mouse' do
  let(:reader) { described_class.allocate }
  let(:popup) { instance_double('OverlayPopup') }
  let(:coordinate_service) { instance_double('CoordinateService') }
  let(:reader_session_mutator) { instance_double('ReaderSessionMutator', update_reader: nil) }
  let(:reader_state_reader) do
    instance_double('ReaderStateReader', mode: :in_book_search, in_book_search_popup: popup,
                                         overlay_hover_index: nil)
  end

  before do
    reader.instance_variable_set(:@reader_state_reader, reader_state_reader)
    reader.instance_variable_set(:@coordinate_service, coordinate_service)
    reader.instance_variable_set(:@reader_session_mutator, reader_session_mutator)
    allow(reader).to receive(:dispatch_input_keys)
    allow(reader).to receive(:draw_screen)
    allow(coordinate_service).to receive(:mouse_to_terminal) { |x, y| { x: x + 1, y: y + 1 } }
  end

  it 'returns false (not consumed) when no bar overlay is active' do
    allow(reader_state_reader).to receive(:mode).and_return(:read)

    expect(reader.send(:handle_bar_overlay_mouse, button: 0, released: true, x: 3, y: 3)).to be(false)
    expect(reader).not_to have_received(:dispatch_input_keys)
  end

  it 'scrolls the active overlay by synthesising arrow keys on the wheel' do
    expect(reader.send(:handle_bar_overlay_mouse, button: 64, released: false, x: 3, y: 3)).to be(true)
    expect(reader).to have_received(:dispatch_input_keys).with(["\e[A"])

    reader.send(:handle_bar_overlay_mouse, button: 65, released: false, x: 3, y: 3)
    expect(reader).to have_received(:dispatch_input_keys).with(["\e[B"])
  end

  it 'previews the hovered row on motion, only when it changes' do
    allow(popup).to receive(:hit_test).with(4, 6).and_return(1)

    expect(reader.send(:handle_bar_overlay_mouse, button: 35, released: false, x: 3, y: 5)).to be(true)

    expect(reader_session_mutator).to have_received(:update_reader).with(overlay_hover_index: 1)
    expect(reader).to have_received(:draw_screen)
  end

  it 'lights up the Paste/Copy buttons on hover (the hover target is the action symbol)' do
    allow(reader_state_reader).to receive(:mode).and_return(:translator)
    allow(reader_state_reader).to receive(:translator_lookup_popup).and_return(popup)
    allow(popup).to receive(:hit_test).and_return(:paste_source)

    reader.send(:handle_bar_overlay_mouse, button: 35, released: false, x: 5, y: 5)

    expect(reader_session_mutator).to have_received(:update_reader).with(overlay_hover_index: :paste_source)
  end

  it 'clears the hover preview when the pointer moves off the entries' do
    allow(reader_state_reader).to receive(:overlay_hover_index).and_return(2)
    allow(popup).to receive(:hit_test).and_return(:inside)

    reader.send(:handle_bar_overlay_mouse, button: 35, released: false, x: 3, y: 5)

    expect(reader_session_mutator).to have_received(:update_reader).with(overlay_hover_index: nil)
  end

  it 'does not rewrite or repaint when the hovered row is unchanged' do
    allow(reader_state_reader).to receive(:overlay_hover_index).and_return(1)
    allow(popup).to receive(:hit_test).and_return(1)

    reader.send(:handle_bar_overlay_mouse, button: 35, released: false, x: 3, y: 5)

    expect(reader_session_mutator).not_to have_received(:update_reader)
    expect(reader).not_to have_received(:draw_screen)
  end

  it 'moves the selection cursor to the pressed row without activating yet' do
    allow(popup).to receive(:hit_test).with(4, 6).and_return(2)

    expect(reader.send(:handle_bar_overlay_mouse, button: 0, released: false, x: 3, y: 5)).to be(true)

    expect(reader_session_mutator).to have_received(:update_reader).with(
      search_selected_index: 2, overlay_hover_index: nil
    )
    expect(reader).not_to have_received(:dispatch_input_keys) # not activated until release
  end

  it 'activates the clicked row on release: writes its index, clears hover, then confirms' do
    allow(popup).to receive(:hit_test).with(4, 6).and_return(2)

    expect(reader.send(:handle_bar_overlay_mouse, button: 0, released: true, x: 3, y: 5)).to be(true)

    expect(reader_session_mutator).to have_received(:update_reader).with(
      search_selected_index: 2, overlay_hover_index: nil
    )
    expect(reader).to have_received(:dispatch_input_keys).with(["\r"])
  end

  it 'dismisses the overlay when the release lands above the panel' do
    allow(popup).to receive(:hit_test).and_return(:outside)

    reader.send(:handle_bar_overlay_mouse, button: 0, released: true, x: 3, y: 1)

    expect(reader_session_mutator).to have_received(:update_reader).with(overlay_hover_index: nil)
    expect(reader).to have_received(:dispatch_input_keys).with(["\e"])
  end

  it 'does nothing on an inert in-panel release but still consumes the event' do
    allow(popup).to receive(:hit_test).and_return(:inside)

    expect(reader.send(:handle_bar_overlay_mouse, button: 0, released: true, x: 3, y: 5)).to be(true)

    expect(reader).not_to have_received(:dispatch_input_keys)
  end

  it 'routes a translator picker activation to its own index field' do
    allow(reader_state_reader).to receive(:mode).and_return(:translator)
    allow(reader_state_reader).to receive(:translator_lookup_popup).and_return(popup)
    allow(popup).to receive(:hit_test).and_return(1)

    reader.send(:handle_bar_overlay_mouse, button: 0, released: true, x: 3, y: 5)

    expect(reader_session_mutator).to have_received(:update_reader).with(
      translator_picker_index: 1, overlay_hover_index: nil
    )
    expect(reader).to have_received(:dispatch_input_keys).with(["\r"])
  end

  it 'opens the language picker on the clicked side via the translator intent' do
    input_controller = instance_double('ReaderInputController', dispatch_reader_intent: nil)
    allow(reader).to receive(:input_controller).and_return(input_controller)
    allow(reader_state_reader).to receive(:mode).and_return(:translator)
    allow(reader_state_reader).to receive(:translator_lookup_popup).and_return(popup)
    allow(popup).to receive(:hit_test).and_return(:picker_source)

    reader.send(:handle_bar_overlay_mouse, button: 0, released: true, x: 5, y: 1)

    expect(input_controller).to have_received(:dispatch_reader_intent).with(:translator_open_picker, :source)
    expect(reader).not_to have_received(:dispatch_input_keys) # not a key-replayed action
  end

  it 'routes the Paste and Copy buttons to their translator intents' do
    input_controller = instance_double('ReaderInputController', dispatch_reader_intent: nil)
    allow(reader).to receive(:input_controller).and_return(input_controller)
    allow(reader_state_reader).to receive(:mode).and_return(:translator)
    allow(reader_state_reader).to receive(:translator_lookup_popup).and_return(popup)

    allow(popup).to receive(:hit_test).and_return(:paste_source)
    reader.send(:handle_bar_overlay_mouse, button: 0, released: true, x: 5, y: 5)
    expect(input_controller).to have_received(:dispatch_reader_intent).with(:translator_paste_source, nil)

    allow(popup).to receive(:hit_test).and_return(:copy_translation)
    reader.send(:handle_bar_overlay_mouse, button: 0, released: true, x: 5, y: 8)
    expect(input_controller).to have_received(:dispatch_reader_intent).with(:translator_copy_translation, nil)
  end

  it 'closes the translator from its red close box (Esc through the editor face)' do
    allow(reader_state_reader).to receive(:mode).and_return(:translator)
    allow(reader_state_reader).to receive(:translator_lookup_popup).and_return(popup)
    allow(popup).to receive(:hit_test).and_return(:translator_close)

    reader.send(:handle_bar_overlay_mouse, button: 0, released: true, x: 5, y: 5)

    expect(reader_session_mutator).to have_received(:update_reader).with(overlay_hover_index: nil)
    expect(reader).to have_received(:dispatch_input_keys).with(["\e"])
  end

  it 'keeps the translator open when the release lands out in the book' do
    allow(reader_state_reader).to receive(:mode).and_return(:translator)
    allow(reader_state_reader).to receive(:translator_lookup_popup).and_return(popup)
    allow(popup).to receive(:hit_test).and_return(:outside)

    reader.send(:handle_bar_overlay_mouse, button: 0, released: true, x: 3, y: 1)

    expect(reader).not_to have_received(:dispatch_input_keys) # never Esc — closes only from the box
  end

  it 'lights up the close box on hover (the hover target is the action symbol)' do
    allow(reader_state_reader).to receive(:mode).and_return(:translator)
    allow(reader_state_reader).to receive(:translator_lookup_popup).and_return(popup)
    allow(popup).to receive(:hit_test).and_return(:translator_close)

    reader.send(:handle_bar_overlay_mouse, button: 35, released: false, x: 5, y: 5)

    expect(reader_session_mutator).to have_received(:update_reader).with(overlay_hover_index: :translator_close)
  end
end
