# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Ui::Components::Screens::MenuScreenComponent do
  include MenuScreenRenderHelpers

  let(:palette) { Shoko::Adapters::Ui::Components::StatusBar::Palette }

  let(:menu_state_reader) do
    instance_double('MenuStateReader', selected: selected, translator_source_lang: 'auto',
                                       translator_target_lang: 'en')
  end
  let(:catalog_service) do
    instance_double('CatalogService',
                    entries: [{ 'name' => 'Moby-Dick', 'size' => 1_200_000 }],
                    scan_status: :done,
                    scan_message: '',
                    cached_library_entries: [])
  end
  let(:annotation_service) { instance_double('AnnotationService', list_all: {}) }
  let(:rss_reader_service) { instance_double('RssReaderService', snapshot: { feeds: [], articles: [] }) }
  let(:config_reader) { instance_double('ConfigReader', load: nil) }
  let(:dependencies) do
    instance_double('Dependencies',
                    menu_state_reader: menu_state_reader,
                    catalog_service: catalog_service,
                    annotation_service: annotation_service,
                    rss_reader_service: rss_reader_service,
                    config_reader: config_reader)
  end
  let(:selected) { 0 }
  let(:component) { described_class.new(dependencies) }

  describe 'preview canvas (rail visible)' do
    before { component.canvas_mode = true }

    it 'renders the live preview for the selection on the canvas surface' do
      writes = render_component(component, width: 84, height: 30)
      text = rendered_text(writes)

      expect(text).to include('Browse Library')
      expect(text).to include('Moby-Dick')
      expect(text).to include('1 book')
      expect(text).to include('ENTER browse the shelf')
      expect(writes.any? { |entry| entry[:text].include?(palette::LANDING_CANVAS_BG) }).to be(true)
    end

    it 'moves the preview with the selection' do
      allow(menu_state_reader).to receive(:selected).and_return(6)

      text = rendered_text(render_component(component, width: 84, height: 30))

      expect(text).to include('Settings')
      expect(text).to include('ENTER adjust settings')
    end

    it 'renders every entry preview without divider glyphs' do
      described_class::MENU_ITEMS.each_index do |index|
        entry_component = described_class.new(dependencies)
        entry_component.canvas_mode = true
        allow(menu_state_reader).to receive(:selected).and_return(index)

        text = rendered_text(render_component(entry_component, width: 76, height: 26))

        expect(text).not_to include('│')
        expect(text).not_to include('┃')
      end
    end

    it 'survives a failing preview provider and still renders the canvas' do
      allow(catalog_service).to receive(:entries).and_raise(StandardError, 'boom')

      text = rendered_text(render_component(component, width: 84, height: 30))

      expect(text).to include('Browse')
    end
  end

  describe 'compact fallback (rail hidden)' do
    before { component.canvas_mode = false }

    it 'renders the centered list without the canvas surface' do
      writes = render_component(component, width: 60, height: 20)
      text = rendered_text(writes)

      expect(text).to include('Browse Library')
      expect(text).to include('Quit')
      expect(writes.none? { |entry| entry[:text].include?(palette::LANDING_CANVAS_BG) }).to be(true)
    end
  end

  describe 'dependency-free rendering' do
    it 'renders with nil dependencies at any size' do
      bare = described_class.new(nil)

      expect { render_component(bare, width: 110, height: 30) }.not_to raise_error
      expect { render_component(bare, width: 60, height: 18) }.not_to raise_error
    end
  end
end
