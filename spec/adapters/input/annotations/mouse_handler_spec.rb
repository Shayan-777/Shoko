# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::Annotations::MouseHandler do
  let(:handler) { described_class.new }

  it 'detects SGR and X10 mouse sequences' do
    sgr = "\e[<0;10;12M"
    x10 = "\e[M" + [32, 40, 50].pack('C*')

    expect(handler.mouse_sequence?(sgr)).to be(true)
    expect(handler.mouse_sequence?(x10)).to be(true)
    expect(handler.mouse_sequence?('q')).to be(false)
  end

  it 'recognizes mouse prefixes for buffering' do
    expect(handler.mouse_prefix?("\e[")).to be(true)
    expect(handler.mouse_prefix?("\e[<")).to be(true)
    expect(handler.mouse_prefix?("\e[M")).to be(true)
    expect(handler.mouse_prefix?("\e[A")).to be(false)
  end

  it 'parses SGR mouse events' do
    event = handler.parse_mouse_event("\e[<0;10;12M")

    expect(event).to eq(button: 0, x: 9, y: 11, released: false)
  end

  it 'parses X10 mouse events' do
    # X10 format: ESC [ M + (button+32, x+32, y+32)
    x10 = "\e[M" + [32, 37, 38].pack('C*')
    event = handler.parse_mouse_event(x10)

    expect(event).to eq(button: 0, x: 4, y: 5, released: false)
  end
end
