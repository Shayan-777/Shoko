# frozen_string_literal: true

require 'spec_helper'
require 'rexml/document'
require 'shoko/adapters/output/formatting/css/element_style_resolver'

RSpec.describe Shoko::Adapters::Output::Formatting::Css::ElementStyleResolver do
  Parser = Shoko::Adapters::Output::Formatting::Css::StylesheetParser

  def resolver_for(css)
    described_class.new(rules: Parser.parse(css))
  end

  def element(xml, xpath)
    REXML::Document.new(xml).elements.to_a(xpath).first
  end

  it 'reports whether any rules are loaded' do
    expect(resolver_for('p { font-weight: bold }').any_rules?).to be(true)
    expect(described_class.new(rules: []).any_rules?).to be(false)
  end

  it 'computes styles from matching rules' do
    resolver = resolver_for('p { font-style: italic; text-align: center }')
    para = element('<body><p>x</p></body>', '//p')

    expect(resolver.computed_style(para)).to include(italic: true, align: :center)
  end

  it 'inherits inheritable properties from ancestors' do
    resolver = resolver_for('section.typ1 p { font-style: italic } section { color: #333 }')
    para = element('<body><section class="typ1"><p><span>x</span></p></section></body>', '//span')

    expect(resolver.computed_style(para)).to include(italic: true, fg: '#333')
  end

  it 'does not inherit non-inheritable properties like margins or display' do
    resolver = resolver_for('div { margin-top: 2em; display: block }')
    span = element('<body><div><span>x</span></div></body>', '//span')

    computed = resolver.computed_style(span)
    expect(computed).not_to have_key(:margin_top)
    expect(computed).not_to have_key(:display)
  end

  it 'lets higher specificity win regardless of source order' do
    resolver = resolver_for('p.special { font-weight: bold } p { font-weight: normal }')
    para = element('<body><p class="special">x</p></body>', '//p')

    expect(resolver.computed_style(para)[:bold]).to be(true)
  end

  it 'lets later rules win at equal specificity' do
    resolver = resolver_for('p { font-weight: bold } p { font-weight: normal }')
    para = element('<body><p>x</p></body>', '//p')

    expect(resolver.computed_style(para)[:bold]).to be(false)
  end

  it 'lets !important beat later and more specific declarations' do
    resolver = resolver_for('p { font-style: normal !important } p.x { font-style: italic }')
    para = element('<body><p class="x">y</p></body>', '//p')

    expect(resolver.computed_style(para)[:italic]).to be(false)
  end

  it 'composes relative font sizes down the tree and buckets them' do
    resolver = resolver_for('div { font-size: 1.5em } div p { font-size: 0.5em }')
    para = element('<body><div><p>x</p></div></body>', '//p')

    expect(resolver.computed_style(para)[:font_size]).to be_within(0.001).of(0.75)
    expect(resolver.inline_styles(para)).to include(small: true)
  end

  it 'exposes display queries' do
    resolver = resolver_for('.hidden { display: none } span.blocky { display: block }')
    doc = '<body><p class="hidden">x</p><span class="blocky">y</span></body>'

    expect(resolver.display_none?(element(doc, '//p'))).to be(true)
    expect(resolver.block_display?(element(doc, '//span'))).to be(true)
  end

  it 'maps computed styles to inline segment styles' do
    resolver = resolver_for('span { font-variant: small-caps; color: red; letter-spacing: .1em }')
    span = element('<body><span>x</span></body>', '//span')

    expect(resolver.inline_styles(span)).to include(small_caps: true, fg: 'red')
  end

  it 'maps computed styles to block typography metadata' do
    css = 'p { text-indent: 1em; margin: 0 2.5em; text-align: justify }'
    resolver = resolver_for(css)
    para = element('<body><p>x</p></body>', '//p')

    metadata = resolver.block_metadata(para)
    expect(metadata).to include(
      align: :justify,
      first_line_indent: 2,
      indent_left: 5,
      indent_right: 5,
      spacing_before: 0,
      spacing_after: 0
    )
  end

  it 'buckets margins into spacing levels' do
    resolver = resolver_for('h1 { margin-top: 3em; margin-bottom: 1em }')
    heading = element('<body><h1>x</h1></body>', '//h1')

    expect(resolver.block_metadata(heading)).to include(spacing_before: 2, spacing_after: 1)
  end

  it 'maps negative text-indent to hanging indent' do
    resolver = resolver_for('p span { padding-left: 1em; text-indent: -1em; display: block }')
    span = element('<body><p><span>verse</span></p></body>', '//span')

    expect(resolver.block_metadata(span)).to include(hanging_indent: 2, indent_left: 2)
  end

  it 'shares computed styles across structurally identical elements' do
    resolver = resolver_for('p { font-style: italic }')
    xml = "<body>#{'<p>x</p>' * 7}</body>"
    paragraphs = REXML::Document.new(xml).elements.to_a('//p')

    styles = paragraphs.map { |para| resolver.computed_style(para) }
    # The structural key looks back three siblings (plus a last-child bit),
    # so runs of identical mid-run elements converge to a shared computed
    # style from the fifth on.
    expect(styles[4]).to equal(styles[5])
  end

  it 'applies :last-child rules to the last of a run of identical siblings' do
    resolver = resolver_for('p { margin-bottom: 1em } p:last-child { margin-bottom: 0 }')
    xml = "<body>#{'<p>x</p>' * 6}</body>"
    paragraphs = REXML::Document.new(xml).elements.to_a('//p')

    metadata = paragraphs.map { |para| resolver.block_metadata(para) }
    expect(metadata[4]).to include(spacing_after: 1)
    expect(metadata[5]).to include(spacing_after: 0)
  end

  it 'does not leak a first-computed :last-child match onto later mid-run siblings' do
    resolver = resolver_for('li:last-child { font-weight: bold }')
    xml = "<body><ul>#{'<li>x</li>' * 6}</ul></body>"
    items = REXML::Document.new(xml).elements.to_a('//li')

    # Compute the last item first so a shared-key regression would poison
    # the middle items with its bold style.
    expect(resolver.computed_style(items[5])).to include(bold: true)
    expect(resolver.computed_style(items[4])).not_to include(bold: true)
  end
end
