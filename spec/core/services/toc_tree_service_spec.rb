# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Core::Services::TocTreeService do
  subject(:service) { described_class.new }

  it 'builds fallback entries from chapters when toc is empty' do
    chapters = [Struct.new(:title).new('Intro'), Struct.new(:title).new('')]
    doc = Struct.new(:toc_entries, :chapters).new([], chapters)

    entries = service.entries_for(doc)

    expect(entries.map(&:title)).to eq(['Intro', 'Chapter 2'])
    expect(entries.map(&:level)).to eq([0, 0])
    expect(entries.map(&:chapter_index)).to eq([0, 1])
  end

  it 'returns filtered entries with ancestors and ignores collapse when filter is active' do
    entries = [
      Shoko::Core::Models::TOCEntry.new(title: 'Chapter 1', href: nil, level: 0, chapter_index: 0),
      Shoko::Core::Models::TOCEntry.new(title: 'Section A', href: nil, level: 1, chapter_index: 0),
      Shoko::Core::Models::TOCEntry.new(title: 'Section B', href: nil, level: 1, chapter_index: 0),
      Shoko::Core::Models::TOCEntry.new(title: 'Chapter 2', href: nil, level: 0, chapter_index: 1)
    ]

    visible = service.visible_indices(entries, collapsed: [0], filter_text: 'section b', filter_active: true)

    expect(visible).to eq([0, 2])
  end

  it 'applies collapse when filter is inactive' do
    entries = [
      Shoko::Core::Models::TOCEntry.new(title: 'Chapter 1', href: nil, level: 0, chapter_index: 0),
      Shoko::Core::Models::TOCEntry.new(title: 'Section A', href: nil, level: 1, chapter_index: 0),
      Shoko::Core::Models::TOCEntry.new(title: 'Section B', href: nil, level: 1, chapter_index: 0),
      Shoko::Core::Models::TOCEntry.new(title: 'Chapter 2', href: nil, level: 0, chapter_index: 1)
    ]

    visible = service.visible_indices(entries, collapsed: [0], filter_text: '', filter_active: false)

    expect(visible).to eq([0, 3])
  end

  it 're-targets hidden selection to a visible entry' do
    entries = [
      Shoko::Core::Models::TOCEntry.new(title: 'Chapter 1', href: nil, level: 0, chapter_index: 0),
      Shoko::Core::Models::TOCEntry.new(title: 'Section A', href: nil, level: 1, chapter_index: 0),
      Shoko::Core::Models::TOCEntry.new(title: 'Chapter 2', href: nil, level: 0, chapter_index: 1)
    ]

    selected = service.ensure_visible_selection(entries, [0], 1, filter_text: '', filter_active: false)

    expect(selected).to eq(0)
  end
end
