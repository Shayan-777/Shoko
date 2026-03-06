# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::Controllers::Reader::InlineLinkNavigator do
  let(:coordinate_service) { instance_double('CoordinateService') }
  let(:rendered_content_reader) { instance_double('RenderedContentReader', rendered_lines: rendered_lines) }
  let(:reader_state_reader) { instance_double('ReaderStateReader', current_chapter: current_chapter) }
  let(:state_controller) { instance_double('StateController', jump_to_chapter_offset: nil) }
  let(:anchor_resolver) { instance_double('AnchorResolver') }
  let(:current_chapter) { 0 }
  let(:chapter_class) { Struct.new(:metadata) }
  let(:chapters) { [chapter_class.new({ source_path: 'OPS/ch1.xhtml' })] }
  let(:document) { instance_double('ReaderDocument', chapters: chapters) }
  let(:document_reader) { -> { document } }
  let(:navigator) do
    described_class.new(
      coordinate_service: coordinate_service,
      rendered_content_reader: rendered_content_reader,
      reader_state_reader: reader_state_reader,
      document_reader: document_reader,
      state_controller: state_controller,
      anchor_resolver: anchor_resolver
    )
  end

  let(:geometry) do
    cells = %w[r e f 2 2].each_with_index.map do |cluster, index|
      Shoko::Adapters::Ui::Rendering::Models::LineCell.new(
        cluster: cluster,
        char_start: index,
        char_end: index + 1,
        display_width: 1,
        screen_x: index
      )
    end
    Shoko::Adapters::Ui::Rendering::Models::LineGeometry.new(
      page_id: 0,
      column_id: 0,
      row: 2,
      column_origin: 1,
      line_offset: 10,
      plain_text: 'ref22',
      styled_text: 'ref22',
      cells: cells
    )
  end

  let(:anchor) do
    Shoko::Core::Models::SelectionAnchor.new(
      page_id: 0,
      column_id: 0,
      geometry_key: geometry.key,
      line_offset: 10,
      cell_index: 3,
      row: 2,
      column_origin: 1
    )
  end

  let(:rendered_lines) do
    {
      geometry.key => {
        geometry: geometry,
        link_spans: [{ start_char: 3, end_char: 5, href: href }],
        chapter_source_path: 'OPS/ch1.xhtml',
      },
    }
  end
  let(:event) { { button: 0, released: true, x: 3, y: 1 } }
  let(:href) { '#note22' }

  before do
    allow(coordinate_service).to receive(:anchor_from_point).and_return(anchor)
  end

  it 'jumps to the resolved in-chapter anchor offset' do
    expect(anchor_resolver).to receive(:line_offset_for_href).with(href: '#note22', chapter_index: 0).and_return(85)
    expect(state_controller).to receive(:jump_to_chapter_offset).with(0, 85)

    expect(navigator.navigate(event)).to be(true)
  end

  it 'resolves cross-chapter hrefs before jumping to anchor offsets' do
    chapters << chapter_class.new({ source_path: 'OPS/ch2.xhtml' })
    cross_chapter_lines = {
      geometry.key => {
        geometry: geometry,
        link_spans: [{ start_char: 3, end_char: 5, href: 'ch2.xhtml#n1' }],
        chapter_source_path: 'OPS/ch1.xhtml',
      },
    }
    allow(rendered_content_reader).to receive(:rendered_lines).and_return(cross_chapter_lines)
    allow(anchor_resolver).to receive(:line_offset_for_href).with(href: 'ch2.xhtml#n1', chapter_index: 1).and_return(12)
    expect(state_controller).to receive(:jump_to_chapter_offset).with(1, 12)

    expect(navigator.navigate(event.merge(x: 4))).to be(true)
  end

  it 'ignores clicks that are not on a link span' do
    non_link_anchor = Shoko::Core::Models::SelectionAnchor.new(
      page_id: 0,
      column_id: 0,
      geometry_key: geometry.key,
      line_offset: 10,
      cell_index: 1,
      row: 2,
      column_origin: 1
    )
    allow(coordinate_service).to receive(:anchor_from_point).and_return(non_link_anchor)
    expect(anchor_resolver).not_to receive(:line_offset_for_href)
    expect(state_controller).not_to receive(:jump_to_chapter_offset)

    expect(navigator.navigate(event)).to be(false)
  end

  it 'returns hovered link metadata for pointer events on a link span' do
    hover = navigator.link_hit_for_event(button: 35, released: false, x: 3, y: 1)

    expect(hover).to eq(
      href: '#note22',
      line_offset: 10,
      start_char: 3,
      end_char: 5,
      chapter_source_path: 'OPS/ch1.xhtml'
    )
  end

  it 'returns nil hover metadata when pointer is not over a link span' do
    non_link_anchor = Shoko::Core::Models::SelectionAnchor.new(
      page_id: 0,
      column_id: 0,
      geometry_key: geometry.key,
      line_offset: 10,
      cell_index: 1,
      row: 2,
      column_origin: 1
    )
    allow(coordinate_service).to receive(:anchor_from_point).and_return(non_link_anchor)

    expect(navigator.link_hit_for_event(button: 35, released: false, x: 1, y: 1)).to be_nil
  end
end
