# frozen_string_literal: true

require 'spec_helper'

# The filter owns the mouse-sequence buffer: it feeds recognised SGR sequences
# to the reader's mouse handler and returns only the tokens that are real
# keyboard input. These exercise it directly against a real MouseHandler, which
# is where the stale-prefix behaviour actually lives.
RSpec.describe Shoko::Adapters::Input::Controllers::ReaderController::InputSequenceFilter do
  let(:mouse_handler) { Shoko::Adapters::Input::Annotations::MouseHandler.new }
  let(:handled) { [] }
  let(:filter) do
    described_class.new(mouse_handler: mouse_handler, handle_mouse_input: ->(input) { handled << input })
  end

  describe '#spurious_post_mouse_key?' do
    it "keeps 'q' after mouse tokens" do
      expect(filter.spurious_post_mouse_key?('q', { saw_mouse: true, saw_prefix: false })).to be(false)
    end

    it 'drops a bare escape after a mouse sequence' do
      expect(filter.spurious_post_mouse_key?("\e", { saw_mouse: true, saw_prefix: false })).to be(true)
    end

    it 'drops a bare escape after a mouse prefix' do
      expect(filter.spurious_post_mouse_key?("\e", { saw_mouse: false, saw_prefix: true })).to be(true)
    end

    it 'keeps a bare escape when no mouse token preceded it' do
      expect(filter.spurious_post_mouse_key?("\e", { saw_mouse: false, saw_prefix: false })).to be(false)
    end
  end

  describe '#filter' do
    it 'passes ordinary keys through untouched' do
      expect(filter.filter(%w[q j k])).to eq(%w[q j k])
    end

    it 'consumes a complete mouse sequence and reports it to the handler' do
      sequence = "\e[<0;10;5M"

      expect(filter.filter([sequence])).to eq([])
      expect(handled).to eq([sequence])
    end

    it 'reassembles a mouse sequence split across tokens' do
      expect(filter.filter(["\e[<0;10;5", 'M'])).to eq([])
      expect(handled).to eq(["\e[<0;10;5M"])
    end

    it "does not trap 'q' behind a stale mouse prefix" do
      filter.filter(["\e["])

      expect(filter.filter(['q'])).to eq(['q'])
      expect(handled).to be_empty
    end

    it 'releases a buffered prefix as real input once it cannot become a mouse sequence' do
      expect(filter.filter(["\e[", 'q'])).to eq(['q'])
      expect(handled).to be_empty
    end
  end
end
