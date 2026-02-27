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
      expect(reader).to receive(:handle_popup_context_click).with(event).and_return(true)

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
end
