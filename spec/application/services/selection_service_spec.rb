# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Services::SelectionService do
  let(:coordinate_service) { Shoko::Application::Services::CoordinateService.new }

  subject(:service) { described_class.new(coordinate_service: coordinate_service) }

  def build_geometry(plain_text:)
    cells = plain_text.chars.each_with_index.map do |char, index|
      Shoko::Adapters::Ui::Rendering::Models::LineCell.new(
        cluster: char,
        char_start: index,
        char_end: index + 1,
        display_width: 1,
        screen_x: index
      )
    end

    Shoko::Adapters::Ui::Rendering::Models::LineGeometry.new(
      page_id: 1,
      column_id: 1,
      row: 2,
      column_origin: 5,
      line_offset: 0,
      plain_text: plain_text,
      styled_text: plain_text,
      cells: cells
    )
  end

  it 'extracts text between explicit selection anchors' do
    geometry = build_geometry(plain_text: 'ab')
    rendered_lines = { geometry.key => { geometry: geometry } }
    selection_range = {
      start: {
        page_id: 1,
        geometry_key: geometry.key,
        line_offset: 0,
        cell_index: 0,
        row: 2,
        column_origin: 5
      },
      end: {
        page_id: 1,
        geometry_key: geometry.key,
        line_offset: 0,
        cell_index: 2,
        row: 2,
        column_origin: 5
      }
    }

    expect(service.extract_text(selection_range, rendered_lines)).to eq('ab')
  end

  it 'normalizes mouse ranges through rendered content' do
    geometry = build_geometry(plain_text: 'ab')
    rendered_content_reader = instance_double(
      'RenderedContentReader',
      rendered_lines: { geometry.key => { geometry: geometry } }
    )

    normalized = service.normalize_range(
      rendered_content_reader: rendered_content_reader,
      selection_range: { start: { x: 4, y: 1 }, end: { x: 5, y: 1 } }
    )

    expect(normalized).to include(:start, :end)
    expect(normalized[:start][:geometry_key]).to eq(geometry.key)
  end
end
