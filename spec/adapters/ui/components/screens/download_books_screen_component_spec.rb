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
      download_status: :done,
      download_message: 'Ready',
      download_count: 1,
      download_progress: 0.0,
      download_query: 'austen',
      download_cursor: 6,
      mode: :download
    )
  end
  let(:dependencies) { instance_double('Dependencies', menu_state_reader: menu_state_reader) }
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
      expect(text).to include('Filter: austen')
      expect(writes.any? { |entry| entry[:row] == 2 && strip_ansi(entry[:text]).include?('─') }).to be(true)
    end
  end
end
