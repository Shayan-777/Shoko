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
    [80, 24],
    [120, 40]
  ].each do |width, height|
    it "renders the canvas download results at #{width}x#{height}" do
      writes = render_component(component, width: width, height: height)
      text = rendered_text(writes)

      expect(text).to include('Download Books')
      expect(text).to include('source: gutendex')
      expect(text).to include('Pride and Prejudice')
      expect(text).to include('Jane Austen · en')
      expect(text).to include('Ready')
      expect(text).not_to include('│')
    end
  end

  it 'renders the source picker as candidate rows when source selection is active' do
    allow(menu_state_reader).to receive_messages(
      mode: :download_source_select,
      download_results: [],
      download_message: '',
      download_source_selected: 1
    )

    writes = render_component(component, width: 80, height: 24)
    text = rendered_text(writes)

    expect(text).to include('Gutendex')
    expect(text).to include('Libgen')
    expect(text).to include('ENTER apply')
  end
end
