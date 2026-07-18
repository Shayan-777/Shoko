# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Ui::Components::Screens::MenuScreenComponent do
  include MenuScreenRenderHelpers

  let(:palette) { Shoko::Adapters::Ui::Components::StatusBar::Palette }

  let(:menu_state_reader) do
    instance_double(Shoko::Adapters::Runtime::SessionState::MenuSnapshotProjectionAdapter, selected: selected, translator_source_lang: 'auto',
                                       translator_target_lang: 'en')
  end
  let(:dependency_kwargs) { { menu_state_reader: menu_state_reader } }
  let(:selected) { 0 }

  # Real destination views are exercised by their own specs; here a stand-in
  # view writes a recognizable marker (and, when handed a registry, tries to
  # register a row region) so we can assert the preview renders the *actual*
  # view read-only rather than a hand-built card.
  def fake_view(marker, registry: nil)
    view = Object.new
    view.define_singleton_method(:render) do |surface, bounds|
      registry&.register(col: 1, row: 4, width: 4, height: 1, action: { type: :list_row })
      surface.write(bounds, 4, 4, marker)
    end
    view
  end

  let(:provider_views) { {} }
  let(:component) do
    described_class.new(**dependency_kwargs, preview_screen_provider: ->(key) { provider_views[key] })
  end

  describe 'preview canvas (rail visible)' do
    before { component.canvas_mode = true }

    it 'renders the real destination view for the highlighted entry' do
      provider_views[:browse] = fake_view('THE-REAL-BROWSE-VIEW')

      text = rendered_text(render_component(component, width: 84, height: 30))

      expect(text).to include('THE-REAL-BROWSE-VIEW')
    end

    it 'moves the preview to the highlighted entry' do
      provider_views[:settings] = fake_view('THE-REAL-SETTINGS-VIEW')
      allow(menu_state_reader).to receive(:selected).and_return(6)

      text = rendered_text(render_component(component, width: 84, height: 30))

      expect(text).to include('THE-REAL-SETTINGS-VIEW')
    end

    it 'renders the preview read-only — the previewed view registers no hit regions' do
      registry = Shoko::Adapters::Ui::State::MenuHitRegistry.new
      preview_component = described_class.new(
        menu_state_reader: menu_state_reader,
        menu_hit_registry: registry,
        preview_screen_provider: ->(key) { provider_views[key] }
      )
      preview_component.canvas_mode = true
      provider_views[:browse] = fake_view('BROWSE', registry: registry)
      registry.begin_frame!

      render_component(preview_component, width: 84, height: 30)

      expect(registry.hit(1, 4)).to be_nil
    end

    it 'shows the quit farewell for the entry that has no view' do
      allow(menu_state_reader).to receive(:selected).and_return(7)

      writes = render_component(component, width: 84, height: 30)
      text = rendered_text(writes)

      expect(text).to include('Quit')
      expect(text).to include('ENTER quit')
      expect(writes.any? { |entry| entry[:text].include?(palette::LANDING_CANVAS_BG) }).to be(true)
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
      bare = described_class.new

      expect { render_component(bare, width: 110, height: 30) }.not_to raise_error
      expect { render_component(bare, width: 60, height: 18) }.not_to raise_error
    end
  end
end
