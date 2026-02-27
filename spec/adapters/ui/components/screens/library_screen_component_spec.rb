# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Ui::Components::Screens::LibraryScreenComponent do
  include MenuScreenRenderHelpers

  let(:observer_registry) { MenuScreenRenderHelpers::NullObserverRegistry.new }
  let(:menu_state_reader) { instance_double('MenuStateReader', browse_selected: 0) }
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
    instance_double('Dependencies', menu_state_reader: menu_state_reader, catalog_service: catalog_service)
  end
  let(:component) { described_class.new(observer_registry, dependencies) }

  [
    [:dark, 80, 24],
    [:light, 80, 24],
    [:dark, 120, 40],
    [:light, 120, 40]
  ].each do |mode, width, height|
    it "renders coherent library layout in #{mode} mode at #{width}x#{height}" do
      writes = with_color_mode(mode) { render_component(component, width: width, height: height) }
      text = rendered_text(writes)

      expect(text).to include('Library (Cached)')
      expect(text).to include('TITLE')
      expect(text).to include('AUTHOR(S)')
      expect(text).to include('cached')
      expect(writes.any? { |entry| entry[:row] == 2 && strip_ansi(entry[:text]).include?('─') }).to be(true)
    end
  end
end
