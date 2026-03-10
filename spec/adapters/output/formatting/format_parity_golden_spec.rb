# frozen_string_literal: true

require 'json'
require 'spec_helper'
require_relative '../../../../lib/shoko/adapters/book_sources/epub/parser/xhtml_content_parser'

RSpec.describe 'Formatting parity across book formats' do
  def build_service
    xhtml_factory = ->(raw) { Shoko::Adapters::BookSources::Epub::XHTMLContentParser.new(raw) }
    resolver = Shoko::Bootstrap::ContainerFactory.send(
      :build_format_parser_resolver,
      xhtml_factory,
      nil
    )
    Shoko::Adapters::Output::Formatting::FormattingService.new(
      format_parser_resolver: resolver,
      xhtml_parser_factory: xhtml_factory,
      runtime_config: Shoko::Adapters::Runtime::NullRuntimeConfig.instance
    )
  end

  def render_signature(service, raw:, format:, path:)
    metadata = {}
    metadata[:format] = format if format
    chapter = Struct.new(:raw_content, :lines, :blocks, :metadata).new(raw, [], nil, metadata)
    doc = double('Doc', get_chapter: chapter, canonical_path: path)

    lines = service.wrap_all(doc, 0, 80, config: double('Config', get: false))
    lines.filter_map do |line|
      text = line.respond_to?(:text) ? line.text.to_s : line.to_s
      next if text.strip.empty?

      metadata = line.respond_to?(:metadata) ? (line.metadata || {}) : {}
      block_type = Shoko::Core::Models::BlockType.canonical(metadata[:block_type] || metadata['block_type'])
      normalized_text = text.lstrip.sub(/\A(?:[│>]\s*)+/, '').strip
      next if normalized_text.empty?

      [block_type || :paragraph, normalized_text]
    end
  end

  it 'renders equivalent heading/quote/paragraph structure for epub, fb2, pdf, rtf, and kindle' do
    quote = 'The glory of my boyhood years.'
    body = 'Body paragraph.'
    heading = 'Chapter 1'

    html = <<~HTML
      <html><body>
        <h1>#{heading}</h1>
        <blockquote><p>#{quote}</p></blockquote>
        <p>#{body}</p>
      </body></html>
    HTML

    fb2 = <<~XML
      <section>
        <title><p>#{heading}</p></title>
        <epigraph><p>#{quote}</p></epigraph>
        <p>#{body}</p>
      </section>
    XML

    pdf = JSON.generate(
      {
        format: 'pdf-layout-v1',
        lines: [
          { text: heading, x: 220.0, italic: false, italic_ratio: 0.0 },
          { break: true },
          { text: quote, x: 260.0, italic: true, italic_ratio: 1.0 },
          { break: true },
          { text: body, x: 72.0, italic: false, italic_ratio: 0.0 },
        ],
      }
    )

    samples = {
      epub: { raw: html, format: nil, path: '/tmp/book.epub' },
      fb2: { raw: fb2, format: :fb2, path: '/tmp/book.fb2' },
      pdf: { raw: pdf, format: :pdf, path: '/tmp/book.pdf' },
      rtf: { raw: html, format: :rtf, path: '/tmp/book.rtf' },
      kindle: { raw: html, format: :mobi, path: '/tmp/book.mobi' }
    }

    service = build_service
    signatures = samples.transform_values do |sample|
      render_signature(service, raw: sample[:raw], format: sample[:format], path: sample[:path])
    end

    expected = [
      [:heading, heading],
      [:quote, quote],
      [:paragraph, body]
    ]

    signatures.each do |format, signature|
      expect(signature).to eq(expected), "#{format} signature mismatch: #{signature.inspect}"
    end
  end
end
