# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Output::Ui::Components::Sidebar::EntriesCalculator do
  Sidebar = Shoko::Adapters::Output::Ui::Components::Sidebar
  TOCEntry = Shoko::Core::Models::TOCEntry

  let(:text_metrics) do
    Class.new do
      def self.visible_length(text)
        text.to_s.length
      end

      def self.wrap_plain_text(text, width)
        [text.to_s[0, width]]
      end
    end
  end

  let(:surface) do
    Class.new do
      def write(*); end
    end.new
  end

  let(:bounds) { Shoko::Adapters::Output::Ui::Components::Rect.new(x: 1, y: 1, width: 60, height: 20) }

  def build_context(document:, selected: 0, filter_active: false, filter: '', collapsed: [])
    sidebar_reader = instance_double(
      'SidebarStateReader',
      sidebar_toc_selected: selected,
      sidebar_toc_filter_active?: filter_active,
      sidebar_toc_filter: filter,
      sidebar_toc_collapsed: collapsed
    )

    Sidebar::RenderContext.new(
      surface,
      bounds,
      document,
      sidebar_state_reader: sidebar_reader,
      text_metrics: text_metrics
    )
  end

  it 'builds fallback entries from chapters when TOC is empty' do
    chapter1 = Struct.new(:title).new('Intro')
    chapter2 = Struct.new(:title).new('Body')
    document = Struct.new(:toc_entries, :chapters, :metadata, :title).new([], [chapter1, chapter2], {}, nil)
    context = build_context(document: document)

    entries = described_class.new(context).calculate

    expect(entries.full.map(&:title)).to eq(['Intro', 'Body'])
    expect(entries.visible_indices).to eq([0, 1])
  end

  it 'keeps matching entry ancestors when filter is active' do
    entries = [
      TOCEntry.new(title: 'Chapter 1', href: nil, level: 1, chapter_index: 0),
      TOCEntry.new(title: 'Section A', href: nil, level: 2, chapter_index: 0),
      TOCEntry.new(title: 'Section B', href: nil, level: 2, chapter_index: 0),
      TOCEntry.new(title: 'Chapter 2', href: nil, level: 1, chapter_index: 1)
    ]
    document = Struct.new(:toc_entries, :chapters, :metadata, :title).new(entries, [], {}, nil)
    context = build_context(document: document, filter_active: true, filter: 'section b')

    result = described_class.new(context).calculate

    expect(result.visible.map(&:title)).to eq(['Chapter 1', 'Section B'])
    expect(result.visible_indices).to eq([0, 2])
  end

  it 'does not apply collapse filtering when filter is active' do
    entries = [
      TOCEntry.new(title: 'Chapter 1', href: nil, level: 1, chapter_index: 0),
      TOCEntry.new(title: 'Section A', href: nil, level: 2, chapter_index: 0),
      TOCEntry.new(title: 'Section B', href: nil, level: 2, chapter_index: 0)
    ]
    document = Struct.new(:toc_entries, :chapters, :metadata, :title).new(entries, [], {}, nil)
    context = build_context(document: document, filter_active: true, filter: 'section', collapsed: [0])

    result = described_class.new(context).calculate

    expect(result.visible.map(&:title)).to include('Section A', 'Section B')
  end

  it 'clamps selected index and maps visible index safely' do
    entries = [
      TOCEntry.new(title: 'Root', href: nil, level: 1, chapter_index: 0),
      TOCEntry.new(title: 'Child', href: nil, level: 2, chapter_index: 0)
    ]
    document = Struct.new(:toc_entries, :chapters, :metadata, :title).new(entries, [], {}, nil)
    context = build_context(document: document, selected: 999, filter_active: false, collapsed: [0])

    collection = described_class.new(context).calculate
    selected_index = Sidebar::SelectedIndexCalculator.new(collection).calculate

    expect(collection.selected_full_index).to eq(1)
    expect(selected_index).to eq(0)
  end
end
