# frozen_string_literal: true

require 'rexml/document'
require 'spec_helper'
require 'shoko/adapters/book_sources/epub/parser/opf/navigation_document_scanner'
require 'shoko/adapters/book_sources/epub/parser/opf/navigation_label_resolver'
require 'shoko/adapters/book_sources/epub/parser/opf/navigation_list_item'
require 'shoko/adapters/book_sources/epub/parser/opf/navigation_traversal'

RSpec.describe 'EPUB navigation text extraction' do
  class NavigationTextExtractionSpecEntryReader
    def initialize(entries = {})
      @entries = entries
    end

    def safe_read_entry(_path)
      @entries.fetch(_path, '<h2><a id="D41416E1998"><span class="label">7</span></a></h2>')
    end

    def read_entry(path)
      safe_read_entry(path)
    end

    def expand_path(base, path)
      [base, path].reject(&:empty?).join('/')
    end

    def opf_relative_path(path)
      path
    end
  end

  let(:resolver) do
    Shoko::Adapters::BookSources::Epub::OPFNavigationLabelResolver.new(
      entry_reader: double('EntryReader'),
      source_path: 'OPS/nav.xhtml'
    )
  end

  it 'extracts nested anchor text from nav list items' do
    document = REXML::Document.new('<li><a href="chapter.xhtml#p7"><span class="label">7</span></a></li>')
    item = document.root

    details = Shoko::Adapters::BookSources::Epub::OPFNavigationListItem.new(item, cleaner: resolver)

    expect(details.title).to eq('7')
  end

  it 'extracts uppercase nested anchor text and hrefs from nav list items' do
    document = REXML::Document.new(
      '<LI><A HREF="chapter.xhtml#p7"><SPAN CLASS="label">7</SPAN></A><OL><LI>Child</LI></OL></LI>'
    )
    item = document.root

    details = Shoko::Adapters::BookSources::Epub::OPFNavigationListItem.new(item, cleaner: resolver)

    expect(details.href).to eq('chapter.xhtml#p7')
    expect(details.title).to eq('7')
  end

  it 'strips raw inline markup from fallback heading labels' do
    scanner = Shoko::Adapters::BookSources::Epub::OPFNavigationDocumentScanner.new(cleaner: resolver)
    content = '<h2 id="p7"><a id="D41416E1998"><span class="label">7</span></a></h2>'

    result = scanner.scan(content)

    expect(result.anchors['p7']).to eq('7')
    expect(result.anchors['D41416E1998']).to eq('7')
    expect(result.headings).to eq(['7'])
  end

  it 'extracts uppercase heading ids with named HTML entities through XML traversal' do
    scanner = Shoko::Adapters::BookSources::Epub::OPFNavigationDocumentScanner.new(cleaner: resolver)
    content = '<H2 ID="p7"><A NAME="D41416E1998"/><SPAN CLASS="label">Chapter&nbsp;7</SPAN></H2>'

    result = scanner.scan(content)

    expect(result.anchors['p7']).to eq('Chapter 7')
    expect(result.anchors['D41416E1998']).to eq('Chapter 7')
    expect(result.headings).to eq(['Chapter 7'])
  end

  it 'indexes self-closing anchor ids inside headings to the surrounding label' do
    scanner = Shoko::Adapters::BookSources::Epub::OPFNavigationDocumentScanner.new(cleaner: resolver)
    content = '<h2><a id="D41416E1998"/><span class="label">7</span></h2>'

    result = scanner.scan(content)

    expect(result.anchors['D41416E1998']).to eq('7')
    expect(result.headings).to eq(['7'])
  end

  it 'resolves empty nav labels from nested heading anchors without leaking markup' do
    resolver = Shoko::Adapters::BookSources::Epub::OPFNavigationLabelResolver.new(
      entry_reader: NavigationTextExtractionSpecEntryReader.new,
      source_path: 'OPS/nav.xhtml'
    )

    title = resolver.resolve(href: 'chapter.xhtml#D41416E1998', title: '')

    expect(title).to eq('7')
  end

  it 'walks uppercase XHTML nav documents case-insensitively' do
    reader = NavigationTextExtractionSpecEntryReader.new(
      'OPS/nav.xhtml' => '<HTML><BODY><NAV TYPE="toc"><OL><LI><A HREF="chapter.xhtml#p7">Seven</A></LI></OL></NAV></BODY></HTML>'
    )
    traversal = Shoko::Adapters::BookSources::Epub::OPFNavigationTraversal.new(entry_reader: reader)

    result = traversal.from_nav_path('OPS/nav.xhtml')

    expect(result.toc_entries.first[:title]).to eq('Seven')
    expect(result.toc_entries.first[:href]).to eq('chapter.xhtml#p7')
  end

  it 'walks uppercase NCX nav maps case-insensitively' do
    reader = NavigationTextExtractionSpecEntryReader.new(
      'OPS/toc.ncx' => '<NCX><NAVMAP><NAVPOINT><NAVLABEL><TEXT>One</TEXT></NAVLABEL><CONTENT SRC="one.xhtml"/></NAVPOINT></NAVMAP></NCX>'
    )
    traversal = Shoko::Adapters::BookSources::Epub::OPFNavigationTraversal.new(entry_reader: reader)

    result = traversal.from_ncx_path('OPS/toc.ncx')

    expect(result.toc_entries.first[:title]).to eq('One')
    expect(result.toc_entries.first[:href]).to eq('one.xhtml')
  end
end
