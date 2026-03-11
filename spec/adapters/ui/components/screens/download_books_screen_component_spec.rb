# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Ui::Components::Screens::DownloadBooksScreenComponent do
  include MenuScreenRenderHelpers

  let(:menu_state_reader) do
    instance_double(
      'MenuStateReader',
      download_results: [
        { title: 'Pride and Prejudice', authors: ['Jane Austen'], languages: ['en'], download_count: 1234 }
      ],
      download_selected: 0,
      download_source_selected: 0,
      download_status: :done,
      download_message: 'Ready',
      download_count: 1,
      download_progress: 0.0,
      download_query: 'austen',
      download_cursor: 6,
      mode: :download
    )
  end
  let(:config_reader) { instance_double('ConfigReader', download_source: :gutendex) }
  let(:dependencies) { instance_double('Dependencies', menu_state_reader: menu_state_reader, config_reader: config_reader) }
  let(:component) { described_class.new(dependencies: dependencies) }

  [
    [:dark, 80, 24],
    [:light, 80, 24],
    [:dark, 120, 40],
    [:light, 120, 40]
  ].each do |mode, width, height|
    it "renders coherent download layout in #{mode} mode at #{width}x#{height}" do
      writes = with_color_mode(mode) { render_component(component, width: width, height: height) }
      text = rendered_text(writes)

      expect(text).to include('Download Books')
      expect(text).to include('SEARCH GUTENDEX')
      expect(text).to include('TITLE')
      expect(text).to include('Gutendex | Filter: austen')
      expect(writes.any? { |entry| entry[:row] == 2 && strip_ansi(entry[:text]).include?('─') }).to be(true)
    end
  end

  it 'renders the source selector options inside the download view when source selection is active' do
    allow(menu_state_reader).to receive_messages(
      mode: :download_source_select,
      download_results: [],
      download_message: '',
      download_source_selected: 1
    )

    writes = with_color_mode(:dark) { render_component(component, width: 80, height: 24) }
    text = rendered_text(writes)

    expect(text).to include('Source')
    expect(text).to include('Gutendex')
    expect(text).to include('Libgen')
    expect(text).to include('Choose a source and press Enter')
  end
end
