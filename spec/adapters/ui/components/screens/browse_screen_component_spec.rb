# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Ui::Components::Screens::BrowseScreenComponent do
  include MenuScreenRenderHelpers

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
  let(:menu_state_writer) { instance_double('MenuStateWriter', update_browse_selected: nil) }
  let(:dependencies) do
    instance_double('Dependencies', menu_state_reader: menu_state_reader, menu_state_writer: menu_state_writer)
  end
  let(:catalog) do
    instance_double(
      'CatalogService',
      entries: [],
      scan_status: :done,
      scan_message: 'Ready',
      metadata_for: { title: 'Book One' },
      size_for: 1_048_576
    )
  end
  let(:component) { described_class.new(catalog, observer_registry, dependencies) }

  before do
    component.filtered_epubs = [
      { 'path' => '/tmp/book-1.epub', 'name' => 'Book One', 'size' => 1_048_576 },
      { 'path' => '/tmp/book-2.epub', 'name' => 'Book Two', 'size' => 2_097_152 }
    ]
  end

  [
    [:dark, 80, 24],
    [:light, 80, 24],
    [:dark, 120, 40],
    [:light, 120, 40]
  ].each do |mode, width, height|
    it "renders coherent browse layout in #{mode} mode at #{width}x#{height}" do
      writes = with_color_mode(mode) { render_component(component, width: width, height: height) }
      text = rendered_text(writes)

      expect(text).to include('Browse Library')
      expect(text).to include('SEARCH')
      expect(text).to include('TITLE')
      expect(text).to include('Filter: book')
      expect(writes.any? { |entry| entry[:row] == 2 && strip_ansi(entry[:text]).include?('─') }).to be(true)
    end
  end
end
