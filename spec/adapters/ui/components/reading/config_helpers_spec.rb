# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Presentation::Ui::Components::Reading::ConfigHelpers do
  # Mock config reader that responds to port methods
  def build_config_reader(highlight_quotes: nil, highlight_keywords: nil, line_spacing: nil)
    Struct.new(:highlight_quotes, :highlight_keywords, :line_spacing, keyword_init: true)
          .new(highlight_quotes: highlight_quotes, highlight_keywords: highlight_keywords, line_spacing: line_spacing)
  end

  it 'defaults to highlighting quotes when unset' do
    reader = build_config_reader(highlight_quotes: nil)
    expect(described_class.highlight_quotes?(reader)).to be(true)
  end

  it 'defaults to not highlighting keywords when unset' do
    reader = build_config_reader(highlight_keywords: nil)
    expect(described_class.highlight_keywords?(reader)).to be(false)
  end

  it 'extracts config_reader from context objects' do
    reader = build_config_reader(line_spacing: :normal)
    context = Struct.new(:config_reader).new(reader)
    expect(described_class.config_reader_from(context)).to eq(reader)
  end

  it 'returns config_reader directly if it responds to line_spacing' do
    reader = build_config_reader(line_spacing: :normal)
    expect(described_class.config_reader_from(reader)).to eq(reader)
  end
end
