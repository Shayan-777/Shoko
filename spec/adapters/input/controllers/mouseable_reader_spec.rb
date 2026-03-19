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

      expect(Shoko::Adapters::Input::Controllers::Sidebar::AnchorResolver).to receive(:new).with(
        hash_including(
          ui_state_reader: ui_state_reader,
          formatting_service: formatting_service,
          layout_service: layout_service,
          config_reader: config_reader,
          sidebar_state_reader: reader_state_reader
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
