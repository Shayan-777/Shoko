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
  let(:menu_session_mutator) { instance_double('MenuSessionMutator', update_browse_selected: nil) }
  let(:dependencies) do
    instance_double('Dependencies', menu_state_reader: menu_state_reader, menu_session_mutator: menu_session_mutator)
  end
  let(:catalog) do
    instance_double(
      'CatalogService',
      entries: [],
      scan_status: :done,
      scan_message: 'Ready',
      metadata_for: { title: 'Book One', authors: ['Gabriel Rockhill'] },
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
    it "renders shared browse shell in #{mode} mode at #{width}x#{height}" do
      writes = with_color_mode(mode) { render_component(component, width: width, height: height) }
      text = rendered_text(writes)

      expect(text).to include('Browse Library')
      expect(text).to include('SEARCH')
      expect(text).to include('RESULTS')
      expect(text).to include('SELECTION')
      expect(text).to include('TITLE')
      expect(text).to include('Filter: book')
      expect(text).to include('Book One')
      expect(writes.any? { |entry| entry[:row] == 2 && strip_ansi(entry[:text]).include?('─') }).to be(true)
    end
  end

  it 'keeps status and footer aligned to the centered content area on wide terminals' do
    allow(catalog).to receive_messages(scan_status: :done, scan_message: 'Loaded 180 books from cache')
    writes = with_color_mode(:dark) { render_component(component, width: 170, height: 54) }

    search_label = writes.find { |entry| strip_ansi(entry[:text]).include?('SEARCH') }
    search_field = writes.find do |entry|
      text = strip_ansi(entry[:text])
      text.include?('[') && text.end_with?(']')
    end
    status_right = writes.find { |entry| strip_ansi(entry[:text]).include?('Loaded 180 books from cache') }
    footer = writes.find { |entry| strip_ansi(entry[:text]).include?('Filter: book') }

    expect(search_label).not_to be_nil
    expect(search_field).not_to be_nil
    expect(status_right).not_to be_nil
    expect(footer).not_to be_nil

    status_right_width = Shoko::Shared::Terminal::TextMetrics.visible_length(strip_ansi(status_right[:text]))
    search_field_width = Shoko::Shared::Terminal::TextMetrics.visible_length(strip_ansi(search_field[:text]))
    status_right_edge = status_right[:col] + status_right_width - 1
    content_right_edge = search_field[:col] + search_field_width - 1

    expect(status_right_edge).to be <= content_right_edge
    expect(footer[:col]).to eq(search_label[:col])
  end

  it 'renders binary-encoded titles without raising encoding errors' do
    binary_title = [0x42, 0x6F, 0x6F, 0x6B, 0x20, 0xFC].pack('C*').force_encoding(Encoding::BINARY)
    allow(catalog).to receive(:metadata_for).and_return({ title: binary_title })
    component.filtered_epubs = [
      { 'path' => '/tmp/book-3.mobi', 'name' => binary_title, 'size' => 512_000 }
    ]

    expect { with_color_mode(:dark) { render_component(component, width: 100, height: 28) } }.not_to raise_error
  end

  it 'renders an inactive search field style when search mode is not active' do
    allow(menu_state_reader).to receive(:search_active?).and_return(false)
    writes = with_color_mode(:dark) { render_component(component, width: 100, height: 28) }
    search_field = writes.find do |entry|
      text = entry[:text].to_s
      text.include?('[') && text.include?(']') && text.include?('book')
    end

    expect(search_field).not_to be_nil
    expect(search_field[:text]).to include(Shoko::Adapters::Ui::Constants::Ui::MENU_DIVIDER_FG)
    expect(search_field[:text]).to include(Shoko::Adapters::Ui::Constants::Ui::COLOR_TEXT_DIM)
  end

  it 'sanitizes control sequences in metadata titles before rendering rows' do
    allow(catalog).to receive(:metadata_for).and_return({ title: "AB\e[31mCD\e[0m\nEF\tGH" })

    writes = with_color_mode(:dark) { render_component(component, width: 120, height: 28) }
    text = strip_ansi(rendered_text(writes))

    expect(text).to include('ABCD EF GH')
    expect(text).not_to include("\e[31m")
  end

  it 'falls back to book name when metadata extraction fails for a row' do
    allow(catalog).to receive(:metadata_for).and_raise(
      Shoko::MalformedMetadataInputError,
      'PDF metadata Info dictionary unreadable'
    )

    expect { with_color_mode(:dark) { render_component(component, width: 120, height: 28) } }.not_to raise_error

    writes = with_color_mode(:dark) { render_component(component, width: 120, height: 28) }
    text = strip_ansi(rendered_text(writes))
    expect(text).to include('Book One')
  end

  it 'renders selection details for the currently highlighted row' do
    writes = with_color_mode(:dark) { render_component(component, width: 100, height: 30) }
    text = strip_ansi(rendered_text(writes))

    expect(text).to include('SELECTION')
    expect(text).to include('File:')
    expect(text).to include('Format:')
    expect(text).to include('book-1.epub')
    expect(text).to include('Gabriel Rockhill')
    expect(text).not_to include('Path:')
    expect(text).to include('Enter opens the selected book')
  end
end
