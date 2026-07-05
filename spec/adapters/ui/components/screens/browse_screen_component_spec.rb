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
    instance_double('Dependencies', menu_state_reader: menu_state_reader, menu_session_mutator: menu_session_mutator)
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
end
