# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Core::Services::CoordinateService do
  subject(:service) { described_class.new }

  it 'converts between mouse and terminal coordinates' do
    expect(service.mouse_to_terminal(0, 0)).to eq(x: 1, y: 1)
    expect(service.terminal_to_mouse(1, 1)).to eq(x: 0, y: 0)
  end

  it 'normalizes selection ranges so start precedes end' do
    range = {
      start: { page_id: 1, geometry_key: 'g', line_offset: 10, cell_index: 2, row: 1, column_origin: 1 },
      end: { page_id: 1, geometry_key: 'g', line_offset: 2, cell_index: 0, row: 1, column_origin: 1 },
    }

    normalized = service.normalize_selection_range(range)
    expect(normalized[:start][:line_offset]).to eq(2)
    expect(normalized[:end][:line_offset]).to eq(10)
  end

  it 'creates anchors from rendered geometry' do
    cells = [
      Shoko::Adapters::Output::Rendering::Models::LineCell.new(
        cluster: 'a',
        char_start: 0,
        char_end: 1,
        display_width: 1,
        screen_x: 0
      ),
      Shoko::Adapters::Output::Rendering::Models::LineCell.new(
        cluster: 'b',
        char_start: 1,
        char_end: 2,
        display_width: 1,
        screen_x: 1
      ),
    ]
    geometry = Shoko::Adapters::Output::Rendering::Models::LineGeometry.new(
      page_id: 1,
      column_id: 1,
      row: 2,
      column_origin: 5,
      line_offset: 0,
      plain_text: 'ab',
      styled_text: 'ab',
      cells: cells
    )
    rendered_lines = { geometry.key => { geometry: geometry } }

    anchor = service.anchor_from_point({ x: 4, y: 1 }, rendered_lines, bias: :leading)
    expect(anchor).to be_a(Shoko::Core::Models::SelectionAnchor)
    expect(anchor.cell_index).to eq(0)
  end
end
