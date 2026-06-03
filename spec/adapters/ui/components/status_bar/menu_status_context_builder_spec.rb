# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Ui::Components::StatusBar::MenuStatusContextBuilder do
  MenuReaderDouble = Struct.new(:mode, :browse_selected)

  def build(mode:, browse_selected: 0, library_count: 0, browse_selection: nil)
    described_class.new(
      menu_state_reader: MenuReaderDouble.new(mode, browse_selected),
      library_count: -> { library_count },
      browse_selection: browse_selection
    ).call
  end

  it 'labels and titles each view from its mode' do
    expect(build(mode: :settings).badge.label).to eq('SETTINGS')
    expect(build(mode: :settings).title).to eq('Settings')
    expect(build(mode: :translator).badge.label).to eq('TRANSLATE')
  end

  it 'collapses sub-modes onto their canonical view' do
    expect(build(mode: :download_search).badge.label).to eq('DOWNLOAD')
    expect(build(mode: :annotation_editor).badge.label).to eq('NOTES')
    expect(build(mode: :dictionary_search).badge.label).to eq('DICTIONARY')
  end

  it 'shows the library size on counted views' do
    expect(build(mode: :menu, library_count: 7).trailing).to eq(['7 books'])
    expect(build(mode: :library, library_count: 1).trailing).to eq(['1 book'])
  end

  it 'mirrors the highlighted book on the browse view' do
    book = { 'path' => '/books/Gatsby.epub', 'title' => 'The Great Gatsby' }
    context = build(
      mode: :browse,
      browse_selected: 4,
      browse_selection: -> { { book: book, index: 4, total: 10 } }
    )

    expect(context.badge.label).to eq('EPUB')
    expect(context.title).to eq('The Great Gatsby')
    expect(context.trailing).to eq(['5 / 10'])
  end

  it 'falls back to a book count when browse has no selection' do
    context = build(mode: :browse, library_count: 12, browse_selection: -> { {} })
    expect(context.badge.label).to eq('BROWSE')
    expect(context.trailing).to eq(['12 books'])
  end

  it 'defaults unknown modes to the menu view' do
    expect(build(mode: :something_new).badge.label).to eq('SHOKO')
  end
end
