# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Ui::Components::Ui::CursorBlink do
  subject(:cursor_host) { cursor_host_class.new }

  let(:cursor_host_class) do
    Class.new do
      include Shoko::Adapters::Ui::Components::Ui::CursorBlink
    end
  end

  def strip_ansi(text)
    text.to_s.gsub(/\e\[[0-9;]*m/, '')
  end

  it 'inserts the cursor glyph inline without replacing following text' do
    allow(cursor_host).to receive(:cursor_state).and_return([true, '|'])

    rendered = cursor_host.inline_cursor_text('abc', 1, width: 4)

    expect(strip_ansi(rendered)).to eq('a|bc')
  end

  it 'keeps inline spacing stable when the blink phase hides the cursor' do
    allow(cursor_host).to receive(:cursor_state).and_return([false, ' '])

    rendered = cursor_host.inline_cursor_text('abc', 1, width: 4)

    expect(strip_ansi(rendered)).to eq('a bc')
  end

  it 'restores active styles after drawing a styled cursor glyph' do
    red = "\e[31m"
    allow(cursor_host).to receive(:cursor_state).and_return([true, '|'])

    rendered = cursor_host.inline_cursor_text(
      "#{red}abc#{Shoko::Shared::Terminal::Ansi::RESET}",
      1,
      width: 4,
      style_prefix: "\e[7m",
      restore_prefix: red
    )

    expect(rendered).to include("\e[7m|#{red}")
    expect(strip_ansi(rendered)).to eq('a|bc')
  end
end
