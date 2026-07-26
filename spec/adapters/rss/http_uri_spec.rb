# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Rss::HttpUri do
  # Feed URLs are IRIs. `URI.parse` rejects any non-ASCII character outright
  # ("URI must be ascii only"), which silently cost the reader every article
  # whose slug contained an umlaut — the majority of a German feed.
  describe '.parse' do
    it 'accepts an address with non-ASCII characters in the path' do
      uri = described_class.parse('https://www.dw.com/de/klassenzimmer-einschlägt/a-78076700')

      expect(uri.host).to eq('www.dw.com')
      expect(uri.path).to eq('/de/klassenzimmer-einschl%C3%A4gt/a-78076700')
    end

    it 'keeps the query intact while encoding the path' do
      uri = described_class.parse('https://www.dw.com/de/gewässer/a-1?maca=de-rss-de-top-1016')

      expect(uri.query).to eq('maca=de-rss-de-top-1016')
      expect(uri.path).to include('%C3%A4')
    end

    it 'encodes non-ASCII in the query too' do
      expect(described_class.parse('https://example.com/search?q=Grüße').query).to eq('q=Gr%C3%BC%C3%9Fe')
    end

    it 'leaves a plain ASCII address untouched' do
      url = 'https://example.com/a/b?c=d&e=f#g'

      expect(described_class.parse(url).to_s).to eq(url)
    end

    it 'does not double-encode an already-encoded address' do
      url = 'https://example.com/de/einschl%C3%A4gt/a-1'

      expect(described_class.parse(url).to_s).to eq(url)
    end

    it 'still rejects a malformed address' do
      expect { described_class.parse('http://exa mple.com/ä') }.to raise_error(URI::InvalidURIError)
    end
  end

  describe '.encode' do
    it 'encodes multi-byte characters as their UTF-8 byte sequence' do
      expect(described_class.encode('ä')).to eq('%C3%A4')
      expect(described_class.encode('日')).to eq('%E6%97%A5')
    end

    it 'preserves reserved delimiters' do
      expect(described_class.encode('https://x.de/a?b=c&d=e#f')).to eq('https://x.de/a?b=c&d=e#f')
    end
  end
end
