# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Rss::FeedParser do
  subject(:parser) { described_class.new }

  it 'parses RSS 2.0 feeds into normalized article payloads' do
    xml = <<~XML
      <rss version="2.0">
        <channel>
          <title>Example RSS</title>
          <link>https://example.com</link>
          <item>
            <title>First Story</title>
            <link>https://example.com/first</link>
            <guid>story-1</guid>
            <description><![CDATA[<p>Hello <strong>world</strong>.</p>]]></description>
            <pubDate>Mon, 06 Apr 2026 08:00:00 GMT</pubDate>
          </item>
        </channel>
      </rss>
    XML

    result = parser.parse(xml)

    expect(result[:title]).to eq('Example RSS')
    expect(result[:site_url]).to eq('https://example.com')
    expect(result[:articles]).to contain_exactly(
      include(
        title: 'First Story',
        url: 'https://example.com/first',
        guid: 'story-1',
        summary: 'Hello world.',
        published_at: '2026-04-06T08:00:00Z'
      )
    )
  end

  it 'parses Atom entries and prefers alternate links' do
    xml = <<~XML
      <feed xmlns="http://www.w3.org/2005/Atom">
        <title>Example Atom</title>
        <link rel="self" href="https://example.com/feed.xml" />
        <link rel="alternate" href="https://example.com" />
        <entry>
          <title>Atom Story</title>
          <id>tag:example.com,2026:story-2</id>
          <updated>2026-04-06T08:15:00Z</updated>
          <author><name>Editor</name></author>
          <link href="https://example.com/atom-story" />
          <summary><![CDATA[<div>Brief summary</div>]]></summary>
        </entry>
      </feed>
    XML

    result = parser.parse(xml)

    expect(result[:title]).to eq('Example Atom')
    expect(result[:site_url]).to eq('https://example.com')
    expect(result[:articles].first).to include(
      title: 'Atom Story',
      author: 'Editor',
      url: 'https://example.com/atom-story',
      summary: 'Brief summary',
      published_at: '2026-04-06T08:15:00Z'
    )
  end

  it 'derives a fallback title from article text when a title is missing' do
    xml = <<~XML
      <rss version="2.0">
        <channel>
          <title>Fallback Feed</title>
          <item>
            <description><![CDATA[<p>Lead sentence.</p><p>More text.</p>]]></description>
          </item>
        </channel>
      </rss>
    XML

    result = parser.parse(xml)

    expect(result[:articles].first[:title]).to eq('Lead sentence.')
  end

  it 'raises a parse error for unsupported root elements' do
    expect { parser.parse('<html></html>') }
      .to raise_error(Shoko::Adapters::Rss::FeedParser::ParseError, /Unsupported feed root/)
  end
end
