# frozen_string_literal: true

require 'spec_helper'
require 'rexml/document'
require 'shoko/adapters/book_sources/css/style_catalog'

RSpec.describe Shoko::Adapters::BookSources::Css::StyleCatalog do
  let(:core_css) { 'p { text-indent: 1em } h1 { text-align: center }' }
  let(:local_css) { 'p { text-indent: 0 }' }

  def chapter_raw(links: [], style: nil)
    link_tags = links.map { |href| %(<link href="#{href}" rel="stylesheet" type="text/css"/>) }.join
    style_tag = style ? "<style>#{style}</style>" : ''
    "<html><head>#{link_tags}#{style_tag}</head><body><p>x</p></body></html>"
  end

  def paragraph_of(raw)
    REXML::Document.new(raw).elements.to_a('//p').first
  end

  it 'builds a resolver from the stylesheets a chapter links' do
    catalog = described_class.new(stylesheets: { 'epub/css/core.css' => core_css })
    raw = chapter_raw(links: ['../css/core.css'])

    resolver = catalog.resolver_for(chapter_source_path: 'epub/text/ch1.xhtml', raw_content: raw)

    expect(resolver).not_to be_nil
    expect(resolver.block_metadata(paragraph_of(raw))).to include(first_line_indent: 2)
  end

  it 'returns nil when the chapter links nothing and has no style blocks' do
    catalog = described_class.new(stylesheets: { 'epub/css/core.css' => core_css })
    raw = chapter_raw

    expect(catalog.resolver_for(chapter_source_path: 'epub/text/ch1.xhtml', raw_content: raw)).to be_nil
  end

  it 'cascades later-linked sheets over earlier ones' do
    catalog = described_class.new(
      stylesheets: { 'css/core.css' => core_css, 'css/local.css' => local_css }
    )
    raw = chapter_raw(links: ['../css/core.css', '../css/local.css'])

    resolver = catalog.resolver_for(chapter_source_path: 'text/ch1.xhtml', raw_content: raw)

    expect(resolver.block_metadata(paragraph_of(raw))).not_to have_key(:first_line_indent)
  end

  it 'parses inline style blocks' do
    catalog = described_class.new(stylesheets: {})
    raw = chapter_raw(style: 'p { font-style: italic }')

    resolver = catalog.resolver_for(chapter_source_path: 'ch1.html', raw_content: raw)

    expect(resolver.inline_styles(paragraph_of(raw))).to include(italic: true)
  end

  it 'applies every sheet to every chapter in apply_all_sheets mode' do
    catalog = described_class.new(stylesheets: { 'kindle.css' => core_css }, apply_all_sheets: true)
    raw = chapter_raw

    resolver = catalog.resolver_for(chapter_source_path: nil, raw_content: raw)

    expect(resolver).not_to be_nil
    expect(resolver.block_metadata(paragraph_of(raw))).to include(first_line_indent: 2)
  end

  it 'ignores links to sheets the catalog does not hold' do
    catalog = described_class.new(stylesheets: { 'css/core.css' => core_css })
    raw = chapter_raw(links: ['../css/missing.css'])

    expect(catalog.resolver_for(chapter_source_path: 'text/ch1.xhtml', raw_content: raw)).to be_nil
  end

  it 'reports stylesheet presence' do
    expect(described_class.new(stylesheets: { 'a.css' => 'p{}' }).any_stylesheets?).to be(true)
    expect(described_class.new(stylesheets: {}).any_stylesheets?).to be(false)
  end

  it 'degrades to nil instead of raising on malformed input' do
    catalog = described_class.new(stylesheets: { 'a.css' => 'p { font-weight: bold }' })

    resolver = catalog.resolver_for(chapter_source_path: nil, raw_content: nil)

    expect(resolver).to be_nil
  end
end
