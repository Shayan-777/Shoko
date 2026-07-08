# frozen_string_literal: true

require 'spec_helper'
require 'time'

RSpec.describe Shoko::Adapters::Ui::Components::Screens::LibraryScreenComponent do
  include MenuScreenRenderHelpers

  let(:palette) { Shoko::Adapters::Ui::Components::StatusBar::Palette }
  let(:menu_state_reader) do
    instance_double('MenuStateReader', library_selected: 0, library_details_open?: false)
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
end
