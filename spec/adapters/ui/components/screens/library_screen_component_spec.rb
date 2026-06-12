# frozen_string_literal: true

require 'spec_helper'
require 'time'

RSpec.describe Shoko::Adapters::Ui::Components::Screens::LibraryScreenComponent do
  include MenuScreenRenderHelpers

  let(:observer_registry) { MenuScreenRenderHelpers::NullObserverRegistry.new }
  let(:menu_state_reader) do
    instance_double('MenuStateReader', browse_selected: 0, library_details_open?: false)
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
    instance_double('Dependencies', menu_state_reader: menu_state_reader, catalog_service: catalog_service)
  end
  let(:component) { described_class.new(observer_registry, dependencies) }

  describe 'relative access labels' do
    it 'formats minute/hour/day/week ranges with non-zero values' do
      expect(component.send(:format_relative_time, 30 * 60)).to eq('30 minutes ago')
      expect(component.send(:format_relative_time, 2 * 3600)).to eq('2 hours ago')
      expect(component.send(:format_relative_time, 86_400)).to eq('yesterday')
      expect(component.send(:format_relative_time, 14 * 86_400)).to eq('2 weeks ago')
    end

    it 'converts ISO timestamps to relative labels' do
      allow(Time).to receive(:now).and_return(Time.parse('2026-02-28T00:00:00Z'))

      expect(component.send(:relative_accessed_label, '2026-02-27T00:00:00Z')).to eq('yesterday')
      expect(component.send(:relative_accessed_label, '2026-02-27T22:00:00Z')).to eq('2 hours ago')
    end
  end

  [
    [:dark, 80, 24],
    [:light, 80, 24],
    [:dark, 120, 40],
    [:light, 120, 40]
  ].each do |mode, width, height|
    it "renders shared library shell in #{mode} mode at #{width}x#{height}" do
      writes = with_color_mode(mode) { render_component(component, width: width, height: height) }
      text = rendered_text(writes)

      expect(text).to include('Library')
      expect(text).to include('CACHED BOOKS')
      expect(text).to include('SPACE shows metadata')
      expect(text).to include('cached')
      expect(writes.any? { |entry| entry[:row] == 2 && strip_ansi(entry[:text]).include?('─') }).to be(true)
    end
  end

  describe 'pre-pagination status markers' do
    let(:catalog_service) do
      instance_double(
        'CatalogService',
        cached_library_entries: [
          { 'title' => 'Done Book', 'open_path' => '/done.cache', 'epub_path' => '/done.epub' },
          { 'title' => 'Building Book', 'open_path' => '/building.cache', 'epub_path' => '/building.epub' },
          { 'title' => 'Queued Book', 'open_path' => '/queued.cache', 'epub_path' => '/queued.epub' }
        ],
        size_for: 100
      )
    end
    let(:menu_state_reader) do
      instance_double(
        'MenuStateReader',
        browse_selected: 0,
        library_details_open?: false,
        prepaginate_active: true,
        prepaginate_paths: ['/done.epub', '/building.epub', '/queued.epub'],
        prepaginate_done: 1
      )
    end

    it 'marks the building book recalculating, the next queued, and leaves the finished one normal' do
      text = strip_ansi(rendered_text(with_color_mode(:dark) { render_component(component, width: 120, height: 30) }))

      expect(text).to include('Done Book')
      expect(text).to include('recalculating')
      expect(text).to include('queued')
    end

    it 'shows no status markers once the batch is inactive' do
      allow(menu_state_reader).to receive(:prepaginate_active).and_return(false)

      text = strip_ansi(rendered_text(with_color_mode(:dark) { render_component(component, width: 120, height: 30) }))

      expect(text).not_to include('recalculating')
      expect(text).not_to include('queued')
    end
  end

  it 'renders a details panel when metadata drawer is toggled open' do
    allow(menu_state_reader).to receive(:library_details_open?).and_return(true)

    writes = with_color_mode(:dark) { render_component(component, width: 120, height: 30) }
    text = rendered_text(writes)

    expect(text).to include('DETAILS')
    expect(text).to include('Authors:')
    expect(text).to include('Cache:')
    expect(text).to include('Inspector visible')
  end
end
