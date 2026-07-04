# frozen_string_literal: true

require 'spec_helper'
require 'shoko/adapters/book_sources/css/stylesheet_parser'

RSpec.describe Shoko::Adapters::BookSources::Css::StylesheetParser do
  def declarations_for(css, selector_index: 0)
    rules = described_class.parse(css)
    rules[selector_index].declarations.to_h { |(key, value, _important)| [key, value] }
  end

  it 'parses rules with normalized declarations' do
    rules = described_class.parse('p { font-style: italic; text-align: center }')

    expect(rules.length).to eq(1)
    expect(rules.first.declarations).to contain_exactly([:italic, true, false], [:align, :center, false])
  end

  it 'splits selector groups into one rule per selector' do
    rules = described_class.parse('h1, h2 { font-weight: bold }')

    expect(rules.length).to eq(2)
    expect(rules.map(&:order)).to eq([0, 1])
  end

  it 'flags !important declarations' do
    rules = described_class.parse('p { font-style: normal !important }')

    expect(rules.first.declarations).to eq([[:italic, false, true]])
  end

  it 'drops unsupported properties at parse time' do
    rules = described_class.parse('p { position: absolute; float: left; font-weight: bold }')

    expect(rules.first.declarations).to eq([[:bold, true, false]])
  end

  it 'drops rules whose every declaration is unsupported' do
    expect(described_class.parse('p { position: absolute }')).to be_empty
  end

  it 'skips comments, @font-face, @page, and statement at-rules' do
    css = <<~CSS
      @charset "utf-8";
      @namespace epub "http://www.idpf.org/2007/ops";
      /* a comment { with braces } */
      @font-face { font-family: X; src: url(x.ttf) }
      @page { margin: 1em }
      p { font-weight: bold }
    CSS

    rules = described_class.parse(css)

    expect(rules.length).to eq(1)
    expect(rules.first.declarations).to eq([[:bold, true, false]])
  end

  it 'keeps rules inside all/screen media queries and skips others' do
    css = <<~CSS
      @media screen { p { font-weight: bold } }
      @media print { p { font-style: italic } }
    CSS

    rules = described_class.parse(css)

    expect(rules.length).to eq(1)
    expect(rules.first.declarations).to eq([[:bold, true, false]])
  end

  it 'recovers from malformed blocks' do
    rules = described_class.parse('p { font-weight: bold } garbage } q { font-style: italic }')

    expect(rules.length).to be >= 1
  end

  it 'normalizes margins into em values and spacing shorthand' do
    declarations = declarations_for('p { margin: 1em 2.5em }')

    expect(declarations[:margin_top]).to eq(1.0)
    expect(declarations[:margin_left]).to eq(2.5)
    expect(declarations[:margin_bottom]).to eq(1.0)
  end

  it 'converts px and pt lengths to em' do
    declarations = declarations_for('p { margin-top: 32px; margin-bottom: 24pt }')

    expect(declarations[:margin_top]).to eq(2.0)
    expect(declarations[:margin_bottom]).to eq(2.0)
  end

  it 'normalizes font-size keywords, percentages, and units' do
    expect(declarations_for('p { font-size: 1.17em }')[:font_size]).to eq({ relative: 1.17 })
    expect(declarations_for('p { font-size: 83% }')[:font_size]).to eq({ relative: 0.83 })
    expect(declarations_for('p { font-size: x-large }')[:font_size]).to eq({ absolute: 1.5 })
  end

  it 'maps text-decoration none to explicit falses' do
    expect(declarations_for('a { text-decoration: none }')).to eq({ underline: false, strikethrough: false })
  end

  it 'recognizes small-caps, super/sub, letter-spacing, and monospace families' do
    css = 'span { font-variant: small-caps; vertical-align: super; letter-spacing: .1em; font-family: "DejaVu Mono" }'
    declarations = declarations_for(css)

    expect(declarations).to include(small_caps: true, superscript: true, tracking: true, code: true)
  end

  it 'extracts colors and ignores non-colors' do
    expect(declarations_for('p { color: #ff0000 }')[:fg]).to eq('#ff0000')
    expect(declarations_for('p { background-color: #ccc }')[:bg]).to eq('#ccc')
    expect(described_class.parse('p { color: inherit }')).to be_empty
  end

  it 'treats borders as boxed markers' do
    expect(declarations_for('div { border: 1px solid #333 }')[:boxed]).to be(true)
    expect(declarations_for('div { border: none }')[:boxed]).to be(false)
  end

  it 'normalizes display values' do
    expect(declarations_for('span { display: block }')[:display]).to eq(:block)
    expect(declarations_for('span { display: none }')[:display]).to eq(:none)
    expect(declarations_for('li { display: inline-block }')[:display]).to eq(:inline)
  end

  it 'parses list-style-type and the list-style shorthand' do
    expect(declarations_for('ul { list-style-type: square }')[:list_style]).to eq(:square)
    expect(declarations_for('ol { list-style: lower-roman outside }')[:list_style]).to eq(:lower_roman)
  end

  it 'computes selector specificity' do
    rules = described_class.parse('p { font-weight: bold } p.big#x { font-weight: bold }')

    expect(rules[0].specificity).to be < rules[1].specificity
  end
end
