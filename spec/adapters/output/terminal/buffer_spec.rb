# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Output::Terminal::TerminalBuffer::Frame do
  def rendered_rows_for(text, enabled:)
    described_class.with_fast_ascii_write(enabled: enabled) do
      frame = described_class.new(60, 2)
      frame.write(1, 1, text)
      frame.rendered_rows
    end
  end

  it 'produces identical output for ASCII text with fast path on and off' do
    text = 'The quick brown fox jumps over the lazy dog 12345'

    fast_rows = rendered_rows_for(text, enabled: true)
    baseline_rows = rendered_rows_for(text, enabled: false)

    expect(fast_rows).to eq(baseline_rows)
  end

  it 'preserves ANSI and tab behavior when fast path is enabled' do
    text = "\e[31mred\e[0m\tcell"

    fast_rows = rendered_rows_for(text, enabled: true)
    baseline_rows = rendered_rows_for(text, enabled: false)

    expect(fast_rows).to eq(baseline_rows)
  end
end
