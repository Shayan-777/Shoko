# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Ui::Components::Screens::SettingsScreenComponent do
  include MenuScreenRenderHelpers

  def build_component_with(kitty_images:)
    component = described_class.new(nil, dependencies: nil)
    component.instance_variable_set(
      :@config_reader,
      double('ConfigReader', kitty_images: kitty_images, theme: :default, download_source: :gutendex)
    )
    component
  end

  it 'marks kitty images disabled when config is false' do
    text, _color = build_component_with(kitty_images: false).send(:display_value_for, :toggle_kitty_images)
    expect(text).to eq('Disabled')
  end

  it 'marks kitty images enabled when config is true' do
    text, _color = build_component_with(kitty_images: true).send(:display_value_for, :toggle_kitty_images)
    expect(text).to eq('Enabled')
  end

  it 'marks kitty images disabled when config is nil' do
    text, _color = build_component_with(kitty_images: nil).send(:display_value_for, :toggle_kitty_images)
    expect(text).to eq('Disabled')
  end

  describe 'render snapshots' do
    let(:menu_state_reader) do
      instance_double(
        Shoko::Adapters::Runtime::SessionState::MenuSnapshotProjectionAdapter,
        settings_selected: 0,
        wipe_cache_cached?: true,
        wipe_cache_downloads?: false,
        wipe_cache_dictionary?: false,
        wipe_cache_annotations?: false,
        wipe_cache_bookmarks?: false,
        wipe_cache_progress?: false,
        wipe_cache_config?: false,
        wipe_cache_nuke?: false
      )
    end
    let(:config_reader) do
      instance_double(
        Shoko::Application::Ports::Outbound::State::ConfigSnapshot,
        view_mode: :single,
        line_spacing: :normal,
        paragraph_style: :book,
        justify: :book,
        book_colors: true,
        download_source: :gutendex,
        page_numbering_mode: :dynamic,
        show_page_numbers: true,
        highlight_quotes: true,
        kitty_images: true,
        prepaginate_on_resize: false,
        theme: :default
      )
    end
    let(:dependencies) do
      instance_double(Shoko::Adapters::Ui::MenuUiDependencies, menu_state_reader: menu_state_reader, config_reader: config_reader,
                      menu_hit_registry: nil)
    end
    let(:component) { described_class.new(nil, dependencies: dependencies) }

    [
      [80, 24],
      [120, 40]
    ].each do |width, height|
      it "renders the canvas settings list at #{width}x#{height}" do
        writes = render_component(component, width: width, height: height)
        text = rendered_text(writes)

        expect(text).to include('Settings')
        expect(text).to include('View Mode')
        expect(text).to include('Download Source')
        expect(text).to include('Go Back')
        expect(text).not_to include('│')
      end
    end

    it 'shows the highlighted setting description in the inspector well on wide canvases' do
      allow(menu_state_reader).to receive(:settings_selected).and_return(23)

      writes = render_component(component, width: 110, height: 30)
      text = strip_ansi(rendered_text(writes))

      expect(text).to include('Nuke everything')
      expect(text).to include('Arm a full reset')
    end

    it 'keeps the selected setting visible near the end of the list' do
      allow(menu_state_reader).to receive(:settings_selected).and_return(23)

      writes = render_component(component, width: 80, height: 24)
      text = strip_ansi(rendered_text(writes))

      expect(text).to include('Nuke everything')
    end
  end
end
