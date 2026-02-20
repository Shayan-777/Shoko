# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Presentation::Ui::Components::Reading::LineGeometryBuilder do
  let(:builder) { described_class.new }
  let(:plain_text) { 'Hello 日本語 😀 world' }

  def build_geometry(text)
    builder.build(
      page_id: 1,
      column_id: 'main',
      row: 2,
      col: 3,
      line_offset: 4,
      plain_text: text,
      styled_text: text
    )
  end

  it 'builds geometry with cell metadata' do
    geometry = build_geometry(plain_text)

    expect(geometry.plain_text).to eq(plain_text)
    expect(geometry.cells).not_to be_empty
    expect(geometry.visible_width).to be > 0
  end

  it 'reuses cached cell arrays when cell cache is enabled' do
    described_class.with_cell_cache(enabled: true) do
      first = build_geometry(plain_text)
      second = build_geometry(plain_text)

      expect(first.cells.object_id).to eq(second.cells.object_id)
    end
  end

  it 'builds new cell arrays when cell cache is disabled' do
    described_class.with_cell_cache(enabled: false) do
      first = build_geometry(plain_text)
      second = build_geometry(plain_text)

      expect(first.cells.object_id).not_to eq(second.cells.object_id)
    end
  end
end
