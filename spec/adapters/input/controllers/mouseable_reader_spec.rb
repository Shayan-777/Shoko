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
end
