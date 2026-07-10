# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Ui::Components::Screens::BrowseScreenComponent do
  include MenuScreenRenderHelpers

  let(:palette) { Shoko::Adapters::Ui::Components::StatusBar::Palette }
  let(:observer_registry) { MenuScreenRenderHelpers::NullObserverRegistry.new }
  let(:menu_state_reader) do
    instance_double(
      'MenuStateReader',
      browse_selected: 0,
      search_query: 'book',
      search_cursor: 4,
      search_active?: true,
      loading_path: nil,
      loading_active?: false,
      loading_progress: 0.0,
      loading_message: nil
    )
  end
  let(:menu_session_mutator) { instance_double('MenuSessionMutator', update_menu: nil) }
  let(:dependencies) do
    instance_double('Dependencies', menu_state_reader: menu_state_reader, menu_session_mutator: menu_session_mutator,
                                    menu_hit_registry: nil)
  end
  let(:catalog) do
    instance_double(
      'CatalogService',
      entries: [],
      scan_status: :done,
      scan_message: 'Ready',
      display_metadata_for: { title: 'Book One', authors: ['Gabriel Rockhill'] },
      metadata_for: {},
      size_for: 1_048_576
    )
  end
  let(:component) { described_class.new(catalog, observer_registry, dependencies) }

  before do
    component.filtered_epubs = [
      { 'path' => '/tmp/book-1.epub', 'name' => 'Book One', 'size' => 1_048_576, 'modified' => '2024-01-01T00:00:00Z' },
      { 'path' => '/tmp/book-2.epub', 'name' => 'Book Two', 'size' => 2_097_152, 'modified' => '2024-01-02T00:00:00Z' }
    ]
  end

  [[80, 24], [120, 40]].each do |width, height|
    it "renders the canvas book blocks at #{width}x#{height}" do
      writes = render_component(component, width: width, height: height)
      text = rendered_text(writes)

      expect(text).to include('Browse Library')
      expect(text).to include('2 books')
      expect(text).to include('Book One')
      expect(text).to include('Gabriel Rockhill · EPUB')
      expect(text).to include('filter: book')
      expect(writes.any? { |entry| entry[:text].include?(palette::LANDING_CANVAS_BG) }).to be(true)
      expect(text).not_to include('│')
      expect(text).not_to include('SEARCH [')
    end
  end

  it 'marks the selected block with the family selection background' do
    writes = render_component(component, width: 100, height: 30)

    expect(writes.any? { |entry| entry[:text].include?(palette::LANDING_SELECTED_BG) }).to be(true)
  end

  it 'shows the inline loading stroke under the loading book' do
    allow(menu_state_reader).to receive_messages(
      loading_active?: true,
      loading_path: '/tmp/book-1.epub',
      loading_progress: 0.5,
      loading_message: 'Parsing chapters'
    )

    text = rendered_text(render_component(component, width: 100, height: 30))

    expect(text).to include('━')
    expect(text).to include('50%')
    expect(text).to include('Parsing chapters')
  end

  it 'shows scan progress while the catalog is scanning' do
    allow(catalog).to receive_messages(scan_status: :scanning, scan_message: 'Scanning for ebooks...')
    component.filtered_epubs = []

    text = rendered_text(render_component(component, width: 100, height: 30))

    expect(text).to include('Scanning for ebooks...')
  end

  it 'renders the empty state when nothing matches' do
    component.filtered_epubs = []

    text = rendered_text(render_component(component, width: 100, height: 30))

    expect(text).to include('No matching books')
  end

  it 'keeps selection clamped and exposes the selected book' do
    allow(menu_state_reader).to receive(:browse_selected).and_return(99)

    expect(component.selected_book['name']).to eq('Book Two')
    expect(component.filtered_count).to eq(2)
    expect(component.book_at(0)['name']).to eq('Book One')
  end

  # The shelf overflows, so the scrollbar is drawn — the case where a row's
  # last column and the bar's column used to be the same column.
  describe 'a shelf that overflows its window' do
    let(:menu_design) { Shoko::Adapters::Ui::Components::MenuDesign }
    let(:long_title) do
      "The Cheka : Lenin's political police : the all-Russian extraordinary commission " \
        'for combating counter-revolution and sabotage, December 1917 to February 1922'
    end
    let(:many_authors) do
      ['Domenico Losurdo', 'Gabriel Rockhill', 'Jodi Dean', 'Vijay Prashad',
       'Michael Parenti', 'Rosa Luxemburg', 'Antonio Gramsci']
    end
    let(:width) { 100 }
    let(:height) { 20 }

    let(:content_x) { menu_design::CanvasFrame::LEFT_INSET + 1 }
    let(:content_width) do
      [width - menu_design::CanvasFrame::LEFT_INSET - menu_design::CanvasFrame::RIGHT_INSET,
       menu_design::CanvasFrame::MAX_CONTENT_WIDTH].min
    end
    let(:bar_col) { content_x + content_width - 1 }
    # The size labels right-align into the metadata column; a block's text
    # stops META_GAP columns short of it. That channel is the invariant.
    let(:meta_column_right) { bar_col - menu_design::CanvasList::RIGHT_GAP - 1 }
    let(:meta_column_left) { meta_column_right - described_class::META_COLUMN + 1 }
    let(:text_right) { meta_column_left - described_class::META_GAP - 1 }

    let(:grid) do
      writes = render_component(component, width: width, height: height)
      rendered_grid(writes, width: width, height: height)
    end

    def body_rows = (menu_design::CanvasFrame::BODY_TOP..(height - 2))

    def rows_showing_the_bar
      body_rows.select { |row| grid[row][bar_col - 1] == menu_design::CanvasList::SCROLL_GLYPH }
    end

    # Just the block's text column — no metadata column, no scrollbar.
    def text_of(row) = grid[row][0, text_right].strip

    before do
      # Fall back to each book's own name rather than one shared metadata title.
      allow(catalog).to receive(:display_metadata_for).and_return({})
      allow(menu_state_reader).to receive(:search_query).and_return('')
      component.filtered_epubs = Array.new(20) do |index|
        { 'path' => "/tmp/book-#{index}.epub", 'name' => "Book #{index}", 'size' => 2_202_009 }
      end
    end

    it 'draws the scrollbar' do
      expect(rows_showing_the_bar).not_to be_empty
    end

    it 'never draws row text into the scrollbar column or the gap beside it' do
      gap = menu_design::CanvasList::RIGHT_GAP

      rows_showing_the_bar.each do |row|
        expect(grid[row][(bar_col - 1 - gap)...(bar_col - 1)]).to eq(' ' * gap)
      end
    end

    it 'keeps the size label whole instead of losing its last cell under the bar' do
      expect(grid.compact.join("\n")).to include('2.1 MB')
    end

    it 'right-aligns the size labels into the metadata column' do
      size_rows = body_rows.select { |row| grid[row].include?('2.1 MB') }

      expect(size_rows).not_to be_empty
      size_rows.each { |row| expect(grid[row][meta_column_right - 1]).to eq('B') }
    end

    it 'holds a clear channel between every block row and the metadata column' do
      component.filtered_epubs = [{ 'path' => '/tmp/cheka.pdf', 'name' => long_title,
                                    'author' => many_authors, 'size' => 2_202_009 }] +
                                 Array.new(19) { |i| { 'path' => "/tmp/b#{i}.epub", 'name' => "Book #{i}" } }

      body_rows.each do |row|
        expect(grid[row][text_right...(meta_column_left - 1)]).to eq(' ' * described_class::META_GAP)
      end
    end

    it 'flows a long title onto the next row rather than cutting it off' do
      component.filtered_epubs = [{ 'path' => '/tmp/cheka.pdf', 'name' => long_title, 'size' => 2_202_009 }] +
                                 Array.new(19) { |i| { 'path' => "/tmp/b#{i}.epub", 'name' => "Book #{i}" } }

      title_row = body_rows.find { |row| grid[row].include?('The Cheka') }
      meta_row = body_rows.find { |row| row > title_row && grid[row].include?('PDF') }
      flowed = (title_row...meta_row).map { |row| text_of(row) }.join(' ')

      expect(meta_row).to be > title_row + 1 # the title took rows of its own
      expect(flowed).to include(long_title)
    end

    it 'flows a long author list onto the next row rather than cutting it off' do
      component.filtered_epubs = [{ 'path' => '/tmp/many.epub', 'name' => 'Class Struggle',
                                    'author' => many_authors, 'size' => 2_202_009 }] +
                                 Array.new(19) { |i| { 'path' => "/tmp/b#{i}.epub", 'name' => "Book #{i}" } }

      author_row = body_rows.find { |row| grid[row].include?('Domenico Losurdo') }
      flowed = [text_of(author_row), text_of(author_row + 1)].join(' ')

      expect(flowed).to eq("#{many_authors.join(', ')} · EPUB")
      expect(grid[author_row]).to include('2.1 MB')
    end

    it 'never ellipsizes a title or an author list' do
      component.filtered_epubs = [{ 'path' => '/tmp/cheka.pdf', 'name' => long_title,
                                    'author' => many_authors, 'size' => 2_202_009 }]

      expect(grid.compact.join("\n")).not_to include('...')
    end
  end
end
