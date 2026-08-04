# frozen_string_literal: true

require 'spec_helper'
require 'rexml/document'
require 'shoko/adapters/output/formatting/css/selector_matcher'

RSpec.describe Shoko::Adapters::Output::Formatting::Css::SelectorMatcher do
  def element(xml, xpath)
    REXML::Document.new(xml).elements.to_a(xpath).first
  end

  def match?(selector, xml, xpath)
    parts = described_class.parse(selector)
    raise "selector did not parse: #{selector}" unless parts

    described_class.match?(element(xml, xpath), parts)
  end

  DOC = <<~XML
    <body xmlns:epub="http://www.idpf.org/2007/ops">
      <section class="kapitel typ1" id="ch1" epub:type="chapter">
        <header class="u1"><h1>Title</h1></header>
        <p class="vers first">line one</p>
        <p class="vers">line two</p>
        <blockquote><p>quoted</p></blockquote>
      </section>
    </body>
  XML

  it 'matches type, class, id, and universal selectors' do
    expect(match?('p', DOC, '//p[1]')).to be(true)
    expect(match?('.vers', DOC, '//p[1]')).to be(true)
    expect(match?('.vers.first', DOC, '//p[1]')).to be(true)
    expect(match?('.vers.first', DOC, '//p[2]')).to be(false)
    expect(match?('#ch1', DOC, '//section')).to be(true)
    expect(match?('*', DOC, '//h1')).to be(true)
  end

  it 'matches compound tag.class selectors' do
    expect(match?('p.vers', DOC, '//p[1]')).to be(true)
    expect(match?('div.vers', DOC, '//p[1]')).to be(false)
  end

  it 'matches descendant and child combinators' do
    expect(match?('section p', DOC, '//p[1]')).to be(true)
    expect(match?('body p', DOC, '//p[1]')).to be(true)
    expect(match?('section > p', DOC, '//p[1]')).to be(true)
    expect(match?('body > p', DOC, '//p[1]')).to be(false)
    expect(match?('blockquote p', DOC, '//blockquote/p')).to be(true)
  end

  it 'matches adjacent sibling combinators and chains' do
    expect(match?('header + p', DOC, '//p[1]')).to be(true)
    expect(match?('header + p', DOC, '//p[2]')).to be(false)
    expect(match?('header + p + p', DOC, '//p[2]')).to be(true)
  end

  it 'matches attribute selectors including namespaced epub|type' do
    expect(match?('[epub|type~="chapter"]', DOC, '//section')).to be(true)
    expect(match?('section[epub|type~="dedication"]', DOC, '//section')).to be(false)
    expect(match?('[id="ch1"]', DOC, '//section')).to be(true)
    expect(match?('[class*="typ"]', DOC, '//section')).to be(true)
  end

  it 'matches :first-child and :last-child' do
    expect(match?('header:first-child', DOC, '//header')).to be(true)
    expect(match?('p:first-child', DOC, '//p[1]')).to be(false)
    expect(match?('blockquote:last-child', DOC, '//blockquote')).to be(true)
  end

  it 'returns nil for unsupported selectors so their rules are dropped' do
    expect(described_class.parse('p:hover')).to be_nil
    expect(described_class.parse('p::first-letter')).to be_nil
    expect(described_class.parse('p ~ q')).to be_nil
    expect(described_class.parse('')).to be_nil
  end

  it 'ranks specificity id > class > type' do
    type = described_class.specificity(described_class.parse('p'))
    klass = described_class.specificity(described_class.parse('.vers'))
    id = described_class.specificity(described_class.parse('#ch1'))

    expect(id).to be > klass
    expect(klass).to be > type
  end
end
