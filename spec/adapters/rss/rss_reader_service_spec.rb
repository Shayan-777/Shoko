# frozen_string_literal: true

require 'spec_helper'
require 'digest'

RSpec.describe Shoko::Adapters::Rss::RssReaderService do
  class RssReaderServiceTestRepository
    attr_reader :snapshot

    def initialize(snapshot = { schema_version: 1, feeds: [], articles: [] })
      @snapshot = snapshot
    end

    def load
      @snapshot
    end

    def save(feeds:, articles:)
      @snapshot = { schema_version: 1, feeds: feeds, articles: articles }
    end

    def update
      next_state = yield(@snapshot)
      save(feeds: next_state[:feeds], articles: next_state[:articles])
    end
  end

  let(:repository) { RssReaderServiceTestRepository.new }
  let(:feed_fetcher) { instance_double(Shoko::Adapters::Rss::FeedFetcher) }
  let(:article_content_fetcher) { instance_double(Shoko::Adapters::Rss::ArticleContentFetcher, fetch: nil) }
  let(:wall_clock) { instance_double(Shoko::Application::Ports::Outbound::WallClock, utc_now: Time.utc(2026, 4, 6, 8, 30, 0)) }

  subject(:service) do
    described_class.new(
      repository: repository,
      feed_fetcher: feed_fetcher,
      wall_clock: wall_clock,
      article_content_fetcher: article_content_fetcher
    )
  end

  def article_id_for(feed_id, payload)
    identity = if payload[:guid].to_s.strip != ''
                 "guid:#{payload[:guid].to_s.strip}"
               elsif payload[:url].to_s.strip != ''
                 "url:#{payload[:url].to_s.strip}"
               else
                 [
                   "title:#{payload[:title].to_s.strip}",
                   "published:#{payload[:published_at].to_s.strip}",
                 ].join('|')
               end
    Digest::SHA256.hexdigest([feed_id, identity].join('|'))
  end

  it 'adds feeds and rejects duplicate subscriptions' do
    payload = {
      url: 'https://example.com/feed.xml',
      title: 'Example Feed',
      site_url: 'https://example.com',
      etag: 'tag-1',
      last_modified: 'Mon, 06 Apr 2026 08:00:00 GMT',
      articles: [
        {
          guid: 'story-1',
          title: 'Top Story',
          summary: 'Summary',
          content: 'Full article',
          url: 'https://example.com/story-1',
          published_at: '2026-04-06T08:00:00Z',
        },
      ],
    }
    allow(feed_fetcher).to receive(:fetch).and_return(payload)

    result = service.add_feed('https://example.com/feed.xml')

    expect(result[:added_count]).to eq(1)
    expect(repository.load[:feeds].map(&:title)).to eq(['Example Feed'])
    expect(repository.load[:articles].map(&:title)).to eq(['Top Story'])

    expect { service.add_feed('https://example.com/feed.xml') }
      .to raise_error(Shoko::Adapters::Rss::FeedFetcher::FetchError, /already subscribed/)
  end

  # Article hydration runs arbitrary third-party HTML through the fetcher,
  # extractor, and entity decoder. Before this was a resilient boundary, a
  # non-Shoko error there (an Encoding::CompatibilityError from a mislabelled
  # page, in the reported case) escaped add_feed, escaped the workflow's
  # `rescue Shoko::Error`, and was swallowed by the async relay's debug log —
  # so adding a feed silently did nothing.
  it 'still subscribes when article hydration raises a non-Shoko error' do
    payload = {
      url: 'https://example.com/feed.xml',
      title: 'Example Feed',
      site_url: 'https://example.com',
      articles: [
        {
          guid: 'story-1',
          title: 'Top Story',
          summary: 'Short excerpt',
          content: '',
          url: 'https://example.com/story-1',
          published_at: '2026-04-06T08:00:00Z',
        },
      ],
    }
    allow(feed_fetcher).to receive(:fetch).and_return(payload)
    allow(article_content_fetcher).to receive(:fetch).and_raise(
      Encoding::CompatibilityError, 'incompatible character encodings: BINARY (ASCII-8BIT) and UTF-8'
    )

    result = service.add_feed('https://example.com/feed.xml')

    expect(result[:added_count]).to eq(1)
    expect(repository.load[:feeds].map(&:title)).to eq(['Example Feed'])
    expect(repository.load[:articles].map(&:title)).to eq(['Top Story'])
  end

  it 'hydrates linked article pages when the feed only provides an excerpt' do
    payload = {
      url: 'https://example.com/feed.xml',
      title: 'Example Feed',
      site_url: 'https://example.com',
      articles: [
        {
          guid: 'story-1',
          title: 'Top Story',
          summary: 'Short excerpt from the feed.',
          content: '',
          url: 'https://example.com/story-1',
          published_at: '2026-04-06T08:00:00Z',
        },
      ],
    }
    allow(feed_fetcher).to receive(:fetch).and_return(payload)
    allow(article_content_fetcher).to receive(:fetch).with('https://example.com/story-1').and_return(
      "Short excerpt from the feed.\n\nThis paragraph only exists on the linked article page."
    )

    service.add_feed('https://example.com/feed.xml')

    stored_article = repository.load[:articles].first
    expect(stored_article.content).to include('This paragraph only exists on the linked article page.')
  end

  it 'keeps the full article from the feed without re-fetching the linked page' do
    full_body = 'The Linux kernel has been facing privilege escalation vulnerabilities. ' * 25
    payload = {
      url: 'https://example.com/feed.xml',
      title: 'Example Feed',
      site_url: 'https://example.com',
      articles: [
        {
          guid: 'story-1',
          title: 'Copy Fail kernel vulnerabilities',
          summary: full_body,
          content: '',
          url: 'https://example.com/story-1',
          published_at: '2026-05-19T00:00:00Z',
        },
      ],
    }
    allow(feed_fetcher).to receive(:fetch).and_return(payload)

    service.add_feed('https://example.com/feed.xml')

    expect(article_content_fetcher).not_to have_received(:fetch)
    stored_article = repository.load[:articles].first
    expect(stored_article.content).to include('privilege escalation vulnerabilities')
  end

  it 'preserves read and starred state across syncs and counts newly added articles' do
    initial_payload = {
      url: 'https://example.com/feed.xml',
      title: 'Example Feed',
      site_url: 'https://example.com',
      etag: 'tag-1',
      last_modified: 'Mon, 06 Apr 2026 08:00:00 GMT',
      articles: [
        {
          guid: 'story-1',
          title: 'Top Story',
          summary: 'Summary',
          content: 'Full article',
          url: 'https://example.com/story-1',
          published_at: '2026-04-06T08:00:00Z',
        },
      ],
    }
    synced_payload = {
      url: 'https://example.com/feed.xml',
      title: 'Example Feed',
      site_url: 'https://example.com',
      etag: 'tag-2',
      last_modified: 'Mon, 06 Apr 2026 09:00:00 GMT',
      articles: [
        {
          guid: 'story-1',
          title: 'Top Story Updated',
          summary: 'Updated summary',
          content: 'Updated article',
          url: 'https://example.com/story-1',
          published_at: '2026-04-06T08:00:00Z',
        },
        {
          guid: 'story-2',
          title: 'Second Story',
          summary: 'Second summary',
          content: 'Second article',
          url: 'https://example.com/story-2',
          published_at: '2026-04-06T08:30:00Z',
        },
      ],
    }
    allow(feed_fetcher).to receive(:fetch).and_return(initial_payload, synced_payload)

    add_result = service.add_feed('https://example.com/feed.xml')
    feed_id = add_result[:feed_key]
    existing_article_id = article_id_for(feed_id, initial_payload[:articles].first)
    service.set_article_read(existing_article_id, read: true)
    service.set_article_starred(existing_article_id, starred: true)

    result = service.sync_all
    updated_article = repository.load[:articles].find { |article| article.id == existing_article_id }

    expect(result[:checked]).to eq(1)
    expect(result[:added]).to eq(1)
    expect(updated_article.title).to eq('Top Story Updated')
    expect(updated_article.read).to be(true)
    expect(updated_article.starred).to be(true)
  end

  it 'keeps feed content when linked article fetching fails' do
    payload = {
      url: 'https://example.com/feed.xml',
      title: 'Example Feed',
      site_url: 'https://example.com',
      articles: [
        {
          guid: 'story-1',
          title: 'Top Story',
          summary: 'Short excerpt from the feed.',
          content: '',
          url: 'https://example.com/story-1',
          published_at: '2026-04-06T08:00:00Z',
        },
      ],
    }
    allow(feed_fetcher).to receive(:fetch).and_return(payload)
    allow(article_content_fetcher).to receive(:fetch).and_raise(
      Shoko::Adapters::Rss::ArticleContentFetcher::FetchError, 'timeout'
    )

    service.add_feed('https://example.com/feed.xml')

    stored_article = repository.load[:articles].first
    expect(stored_article.content).to eq('Short excerpt from the feed.')
  end

  it 'projects feeds and articles by scope and query' do
    feed = Shoko::Core::Models::RssFeed.new(
      id: 'feed-1',
      url: 'https://example.com/feed.xml',
      title: 'Daily Planet'
    )
    repository.save(
      feeds: [feed],
      articles: [
        Shoko::Core::Models::RssArticle.new(
          id: 'article-1',
          feed_id: 'feed-1',
          title: 'Lois Investigates',
          author: 'Clark',
          summary: 'City hall story',
          content: 'Full article',
          published_at: '2026-04-06T08:00:00Z',
          read: false,
          starred: false
        ),
        Shoko::Core::Models::RssArticle.new(
          id: 'article-2',
          feed_id: 'feed-1',
          title: 'Sports Desk',
          author: 'Jimmy',
          summary: 'Baseball roundup',
          content: 'Game report',
          published_at: '2026-04-06T07:00:00Z',
          read: true,
          starred: true
        ),
      ]
    )

    unread_feeds = service.feed_projection(snapshot: service.snapshot, scope: :unread)
    filtered_articles = service.article_projection(
      snapshot: service.snapshot,
      selected_feed_key: 'feed-1',
      scope: :starred,
      query: 'sports jimmy'
    )

    expect(unread_feeds).to include(include(key: 'feed-1', unread_count: 1))
    expect(filtered_articles).to contain_exactly(include(id: 'article-2', starred: true))
  end

  it 'removes feeds and updates article flags in place' do
    feed = Shoko::Core::Models::RssFeed.new(id: 'feed-1', url: 'https://example.com/feed.xml', title: 'Daily Planet')
    article = Shoko::Core::Models::RssArticle.new(
      id: 'article-1',
      feed_id: 'feed-1',
      title: 'Morning Edition',
      read: false,
      starred: false
    )
    repository.save(feeds: [feed], articles: [article])

    service.set_article_read('article-1', read: true)
    service.set_article_starred('article-1', starred: true)

    updated_article = repository.load[:articles].first
    expect(updated_article.read).to be(true)
    expect(updated_article.starred).to be(true)

    service.remove_feed('feed-1')

    expect(repository.load[:feeds]).to eq([])
    expect(repository.load[:articles]).to eq([])
  end

  context 'when the store is mutated while a sync is fetching' do
    let(:initial_payload) do
      {
        url: 'https://example.com/feed.xml',
        title: 'Example Feed',
        site_url: 'https://example.com',
        articles: [
          {
            guid: 'story-1',
            title: 'Top Story',
            summary: 'Summary',
            content: 'Full article',
            url: 'https://example.com/story-1',
            published_at: '2026-04-06T08:00:00Z',
          },
        ],
      }
    end

    it 'keeps a read flag set between the fetch and the merge' do
      allow(feed_fetcher).to receive(:fetch).and_return(initial_payload)
      add_result = service.add_feed('https://example.com/feed.xml')
      article_id = article_id_for(add_result[:feed_key], initial_payload[:articles].first)

      # The mark-read lands while the sync's network phase runs — exactly
      # the window the old load→fetch→save cycle used to clobber.
      allow(feed_fetcher).to receive(:fetch) do
        service.set_article_read(article_id, read: true)
        initial_payload
      end

      service.sync_all

      synced = repository.load[:articles].find { |article| article.id == article_id }
      expect(synced.read).to be(true)
    end

    it 'keeps a feed removed between the fetch and the merge' do
      allow(feed_fetcher).to receive(:fetch).and_return(initial_payload)
      add_result = service.add_feed('https://example.com/feed.xml')
      feed_id = add_result[:feed_key]

      allow(feed_fetcher).to receive(:fetch) do
        service.remove_feed(feed_id)
        initial_payload
      end

      result = service.sync_all

      expect(repository.load[:feeds]).to eq([])
      expect(repository.load[:articles]).to eq([])
      expect(result[:snapshot][:feeds]).to eq([])
    end
  end
end
