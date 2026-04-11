# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Rss::RssReaderService do
  class RssReaderServiceLiveSpecRepository
    attr_reader :snapshot

    def initialize
      @snapshot = { schema_version: 1, feeds: [], articles: [] }
    end

    def load
      @snapshot
    end

    def save(feeds:, articles:)
      @snapshot = { schema_version: 1, feeds: feeds, articles: articles }
    end
  end

  it 'hydrates full linked content for Jeff Geerling feed entries', :requires_live_rss do
    repository = RssReaderServiceLiveSpecRepository.new
    service = described_class.new(
      repository: repository,
      feed_fetcher: Shoko::Adapters::Rss::FeedFetcher.new,
      wall_clock: Shoko::Adapters::Runtime::SystemWallClockAdapter.new,
      article_content_fetcher: Shoko::Adapters::Rss::ArticleContentFetcher.new
    )

    result = service.add_feed('https://www.jeffgeerling.com/blog.xml')
    feed_id = result[:feed_key]
    article = repository.load[:articles].find { |entry| entry.feed_id == feed_id }

    expect(article).not_to be_nil
    expect(article.content.length).to be > article.summary.length + 500
    expect(article.content).to include('What better way to do it than through Wi-Fi?')
  end
end
