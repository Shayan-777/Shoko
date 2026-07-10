# frozen_string_literal: true

require 'spec_helper'
require 'time'

RSpec.describe Shoko::Adapters::Ui::Components::Screens::LibraryScreenComponent do
  include MenuScreenRenderHelpers

  let(:palette) { Shoko::Adapters::Ui::Components::StatusBar::Palette }
  let(:menu_state_reader) do
    instance_double('MenuStateReader', library_selected: 0, library_details_open?: false,
                                       prepaginate_active: false, prepaginate_paths: [], prepaginate_done: [])
  end
  let(:catalog_service) do
    instance_double(
      'CatalogService',
      cached_library_entries: [
        {
          'title' => 'Cached Book',
          'authors' => 'Author',
          'year' => '2024',
          'last_accessed' => '2025-01-01T00:00:00Z',
          'size_bytes' => 1_234_567,
          'open_path' => '/tmp/cached.cache',
          'epub_path' => '/tmp/cached.epub'
        }
      ],
      size_for: 1_234_567
    )
  end
  let(:dependencies) do
    instance_double('Dependencies', menu_state_reader: menu_state_reader, catalog_service: catalog_service,
                                    menu_hit_registry: nil)
  end
  let(:component) { described_class.new(dependencies) }

  describe 'relative access labels' do
    it 'converts ISO timestamps to relative labels' do
      allow(Time).to receive(:now).and_return(Time.parse('2026-02-28T00:00:00Z'))

      expect(component.send(:relative_accessed_label, '2026-02-27T00:00:00Z')).to eq('yesterday')
      expect(component.send(:relative_accessed_label, '2026-02-27T22:00:00Z')).to eq('2 hours ago')
      expect(component.send(:relative_accessed_label, '2026-02-14T00:00:00Z')).to eq('2 weeks ago')
    end

    it 'degrades unparseable timestamps to an empty label' do
      expect(component.send(:relative_accessed_label, 'not-a-time')).to eq('')
      expect(component.send(:relative_accessed_label, nil)).to eq('')
    end
  end

  [[80, 24], [120, 40]].each do |width, height|
    it "renders the canvas library list at #{width}x#{height}" do
      writes = render_component(component, width: width, height: height)
      text = rendered_text(writes)

      expect(text).to include('Library')
      expect(text).to include('1 cached')
      expect(text).to include('Cached Book')
      expect(writes.any? { |entry| entry[:text].include?(palette::LANDING_CANVAS_BG) }).to be(true)
      expect(text).not_to include('│')
    end
  end

  it 'raises the inspector well when the metadata drawer is open' do
    allow(menu_state_reader).to receive(:library_details_open?).and_return(true)

    writes = render_component(component, width: 110, height: 30)
    text = rendered_text(writes)

    expect(text).to include('Authors:')
    expect(text).to include('cached.epub')
    expect(writes.any? { |entry| entry[:text].include?(palette::TRANS_FIELD_BG) }).to be(true)
  end

  it 'renders the empty state when no books are cached' do
    allow(catalog_service).to receive(:cached_library_entries).and_return([])

    text = rendered_text(render_component(component, width: 100, height: 28))

    expect(text).to include('No cached books yet')
  end

  describe 'a cached title too long for one row' do
    let(:menu_design) { Shoko::Adapters::Ui::Components::MenuDesign }
    let(:long_title) do
      "The Cheka : Lenin's political police : the all-Russian extraordinary commission " \
        'for combating counter-revolution and sabotage, December 1917 to February 1922'
    end
    let(:width) { 100 }
    let(:height) { 24 }

    let(:content_x) { menu_design::CanvasFrame::LEFT_INSET + 1 }
    let(:content_width) do
      [width - menu_design::CanvasFrame::LEFT_INSET - menu_design::CanvasFrame::RIGHT_INSET,
       menu_design::CanvasFrame::MAX_CONTENT_WIDTH].min
    end
    let(:bar_col) { content_x + content_width - 1 }
    let(:accessed_column_right) { bar_col - menu_design::CanvasList::RIGHT_GAP - 1 }
    let(:accessed_column_left) { accessed_column_right - described_class::ACCESSED_COLUMN + 1 }
    let(:text_right) { accessed_column_left - described_class::ACCESSED_GAP - 1 }

    let(:grid) do
      writes = render_component(component, width: width, height: height)
      rendered_grid(writes, width: width, height: height)
    end

    def body_rows = (menu_design::CanvasFrame::BODY_TOP..(height - 2))
    def text_of(row) = grid[row][0, text_right].strip

    def entry(title, accessed: '2026-02-27T00:00:00Z')
      { 'title' => title, 'authors' => 'Author', 'year' => '2024', 'last_accessed' => accessed,
        'size_bytes' => 1_234_567, 'open_path' => '/tmp/x.cache', 'epub_path' => '/tmp/x.epub' }
    end

    before do
      allow(Time).to receive(:now).and_return(Time.parse('2026-02-28T00:00:00Z'))
      allow(catalog_service).to receive(:cached_library_entries)
        .and_return([entry(long_title)] + Array.new(10) { |i| entry("Book #{i}") })
      component.invalidate_cache!
    end

    it 'flows the title onto further rows rather than cutting it off' do
      title_row = body_rows.find { |row| grid[row].include?('The Cheka') }
      next_row = body_rows.find { |row| row > title_row && grid[row].include?('Book 0') }
      flowed = (title_row...next_row).map { |row| text_of(row) }.join(' ')

      expect(next_row).to be > title_row + 1 # the title took rows of its own
      expect(flowed).to include(long_title)
    end

    it 'indents the wrapped rows under the number column' do
      title_row = body_rows.find { |row| grid[row].include?('The Cheka') }
      title_col = grid[title_row].index('The Cheka') + 1

      expect(grid[title_row + 1][0, title_col - 1].strip).to be_empty
      expect(grid[title_row + 1][title_col - 1]).not_to eq(' ')
    end

    it 'holds a clear channel between every row and the accessed column' do
      body_rows.each do |row|
        expect(grid[row][text_right...(accessed_column_left - 1)])
          .to eq(' ' * described_class::ACCESSED_GAP)
      end
    end

    it 'right-aligns the accessed labels into their column' do
      row = body_rows.find { |line| grid[line].include?('yesterday') }

      expect(grid[row][accessed_column_right - 1]).to eq('y')
    end

    it 'never ellipsizes a title' do
      expect(grid.compact.join("\n")).not_to include('...')
    end
  end
end
