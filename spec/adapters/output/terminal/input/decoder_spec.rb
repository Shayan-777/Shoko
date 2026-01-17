# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Output::Terminal::TerminalInput::Decoder do
  it 'returns a full X10 mouse sequence as a single token' do
    decoder = described_class.new
    sequence = "\e[M#{[32, 40, 50].pack('C*')}"

    decoder.feed(sequence)

    token = decoder.next_token
    expect(token.bytesize).to eq(6)
    expect(token.bytes.first(3)).to eq([0x1B, 0x5B, 0x4D])
    expect(token.bytes.last(3)).to eq([32, 40, 50])
    expect(decoder.next_token).to be_nil
  end

  it 'waits for the full X10 mouse sequence before emitting a token' do
    decoder = described_class.new(sequence_timeout: 0.5)
    part = "\e[M"

    decoder.feed(part)
    expect(decoder.next_token).to be_nil

    decoder.feed([32, 40, 50].pack('C*'))
    token = decoder.next_token
    expect(token.bytes.first(3)).to eq([0x1B, 0x5B, 0x4D])
  end

  it 'normalizes 8-bit CSI X10 mouse sequences to ESC-prefixed tokens' do
    decoder = described_class.new
    sequence = [0x9B, 0x4D, 32, 40, 50].pack('C*')

    decoder.feed(sequence)

    token = decoder.next_token
    expect(token.bytes).to eq([0x1B, 0x5B, 0x4D, 32, 40, 50])
  end
end
