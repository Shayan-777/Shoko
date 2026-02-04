# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Output::Ui::Components::UI::AnnotationListInput do
  it 'converts dash prefix into bullet when followed by space' do
    text, cursor = described_class.insert_character('', 0, '-')
    text, cursor = described_class.insert_character(text, cursor, ' ')

    expect(text).to eq("● ")
    expect(cursor).to eq(2)
  end

  it 'continues bullet list on enter' do
    text = "● item"
    text, cursor = described_class.insert_newline(text, text.length)

    expect(text).to eq("● item\n● ")
    expect(cursor).to eq("● item\n● ".length)
  end

  it 'exits bullet list on empty item' do
    text = "● "
    text, cursor = described_class.insert_newline(text, text.length)

    expect(text).to eq("\n")
    expect(cursor).to eq(1)
  end

  it 'continues numbered list on enter' do
    text = "1. item"
    text, cursor = described_class.insert_newline(text, text.length)

    expect(text).to eq("1. item\n2. ")
    expect(cursor).to eq("1. item\n2. ".length)
  end

  it 'exits numbered list on empty item' do
    text = "2. "
    text, cursor = described_class.insert_newline(text, text.length)

    expect(text).to eq("\n")
    expect(cursor).to eq(1)
  end
end
