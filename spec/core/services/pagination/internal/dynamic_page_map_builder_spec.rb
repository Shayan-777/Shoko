# frozen_string_literal: true

require 'spec_helper'
require 'shoko/core/services/pagination/internal/dynamic_page_map_builder'
require 'shoko/application/ports/outbound/formatting/display_line'
require 'shoko/core/models/content_block'

RSpec.describe Shoko::Core::Services::Pagination::Internal::DynamicPageMapBuilder do
  DisplayLine = Shoko::Application::Ports::Outbound::Formatting::DisplayLine

  def line(text, block_type, spacer: false)
    metadata = { block_type: block_type }
    metadata[:spacer] = true if spacer
    DisplayLine.new(text: text, segments: [], metadata: metadata)
  end

  def blank
    line('', nil, spacer: true)
  end

  def doc_for(lines)
    chapter = Struct.new(:lines).new(nil)
    formatter = Class.new do
      define_method(:initialize) { |wrapped| @wrapped = wrapped }
      define_method(:wrap_all) { |*_args, **_kwargs| @wrapped }
      define_method(:plain_lines_for) { |*_args| @wrapped.map(&:text) }
    end.new(lines)
    doc = Struct.new(:chapter, :formatter) do
      def chapter_count = 1
      def get_chapter(_index) = chapter
    end.new(chapter, formatter)
    [doc, formatter]
  end

  def build_pages(lines, per_page)
    doc, formatter = doc_for(lines)
    described_class.build(
      doc, 40, per_page,
      text_metrics: Shoko::Shared::Terminal::TextMetrics,
      chapter_formatter: formatter
    )
  end

  it 'keeps a heading with its first lines of prose instead of stranding it' do
    lines = [
      line('prose one', :paragraph), line('prose two', :paragraph), line('prose three', :paragraph),
      line('prose four', :paragraph),
      line('Chapter Two', :heading),
      blank,
      line('body one', :paragraph), line('body two', :paragraph),
    ]

    pages = build_pages(lines, 5)

    expect(pages.length).to eq(2)
    expect(pages[0][:end_line]).to eq(3)
    expect(pages[1][:lines].first.text).to eq('Chapter Two')
  end

  it 'places a heading normally when there is room for it and its prose' do
    lines = [
      line('Chapter One', :heading),
      blank,
      line('body one', :paragraph), line('body two', :paragraph),
    ]

    pages = build_pages(lines, 5)

    expect(pages.length).to eq(1)
  end

  it 'does not leave the lone first line of a paragraph at a page bottom' do
    lines = [
      line('prose one', :paragraph), line('prose two', :paragraph), line('prose three', :paragraph),
      blank,
      line('new para first', :paragraph), line('new para second', :paragraph),
    ]

    pages = build_pages(lines, 5)

    expect(pages.length).to eq(2)
    expect(pages[1][:lines].map(&:text)).to eq(['new para first', 'new para second'])
  end

  it 'still fills pages when a heading opens an empty page' do
    lines = [line('Only Heading', :heading)] + Array.new(9) { |i| line("body #{i}", :paragraph) }

    pages = build_pages(lines, 4)

    expect(pages.first[:lines].first.text).to eq('Only Heading')
    expect(pages.sum { |page| page[:lines].length }).to eq(10)
  end
end
