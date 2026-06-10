# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Workflows::Menu::RssReaderWorkflow do
  class RssReaderWorkflowTestMenuSessionStore
    include Shoko::Application::Ports::Outbound::MenuSessionStore

    attr_reader :snapshot

    def initialize(snapshot)
      @snapshot = snapshot
    end

    def load
      @snapshot
    end

    def save(snapshot)
      @snapshot = snapshot
    end
  end

  class RssReaderWorkflowTestMenuTransientStore
    include Shoko::Application::Ports::Outbound::MenuTransientStore

    attr_reader :snapshot

    def initialize(snapshot)
      @snapshot = snapshot
    end

    def load
      @snapshot
    end

    def save(snapshot)
      @snapshot = snapshot
    end
  end

  let(:service) { instance_double('RssReaderService') }
  let(:menu_session_store) do
    RssReaderWorkflowTestMenuSessionStore.new(
      Shoko::Application::Ports::Outbound::State::MenuSessionSnapshot.build(
        mode: :rss_reader,
        rss_scope: :all,
        rss_selected_feed_key: '__all__',
        rss_selected_article_id: nil,
        rss_filter_query: '',
        rss_focus: :feeds,
        rss_content_scroll: 4
      )
    )
  end
  let(:menu_transient_store) do
    RssReaderWorkflowTestMenuTransientStore.new(
      Shoko::Application::Ports::Outbound::State::MenuTransientSnapshot.build(
        rss_feeds: [],
        rss_articles: [],
        rss_status: :empty,
        rss_message: 'Press A to add a feed URL'
      )
    )
  end
  let(:snapshot) { { schema_version: 1, feeds: [:feed], articles: [:article] } }
  let(:feeds) do
    [
      { key: '__all__', title: 'All Feeds', count: 2, unread_count: 1, article_count: 2 },
      { key: 'feed-1', title: 'Daily Planet', count: 2, unread_count: 1, article_count: 2 }
    ]
  end
  let(:articles) do
    [
      { id: 'article-1', feed_id: 'feed-1', feed_title: 'Daily Planet', title: 'Morning Edition', read: false, starred: false }
    ]
  end

  subject(:workflow) do
    described_class.new(
      rss_reader_service: service,
      menu_session_store: menu_session_store,
      menu_transient_store: menu_transient_store
    )
  end

  before do
    allow(service).to receive(:snapshot).and_return(snapshot)
    allow(service).to receive(:feed_projection).and_return(feeds)
    allow(service).to receive(:normalize_feed_key).and_return('feed-1')
    allow(service).to receive(:article_projection).and_return(articles)
    allow(service).to receive(:normalize_article_id).and_return('article-1')
    allow(service).to receive(:last_synced_at).and_return('2026-04-06T08:00:00Z')
  end

  it 'populates menu session and transient state when opening the reader' do
    workflow.open_reader

    expect(menu_session_store.load.rss_selected_feed_key).to eq('feed-1')
    expect(menu_session_store.load.rss_selected_article_id).to eq('article-1')
    expect(menu_transient_store.load.rss_feeds).to eq(feeds)
    expect(menu_transient_store.load.rss_articles).to eq(articles)
    expect(menu_transient_store.load.rss_status).to eq(:ready)
    expect(menu_transient_store.load.rss_last_synced_at).to eq('2026-04-06T08:00:00Z')
  end

  it 'adds a feed and selects it in the refreshed projection' do
    allow(service).to receive(:add_feed).with('https://example.com/feed.xml').and_return(
      snapshot: snapshot,
      feed_key: 'feed-1',
      added_count: 2
    )

    workflow.add_feed('https://example.com/feed.xml')

    expect(menu_session_store.load.rss_selected_feed_key).to eq('feed-1')
    expect(menu_session_store.load.rss_content_scroll).to eq(0)
    expect(menu_transient_store.load.rss_message).to eq('Added 2 articles from the new feed')
  end

  it 'reports an error when attempting to remove the synthetic all-feeds entry' do
    workflow.remove_feed('__all__')

    expect(menu_transient_store.load.rss_status).to eq(:error)
    expect(menu_transient_store.load.rss_message).to eq('Select a feed to remove')
  end

  it 'updates article state through the service and preserves selection' do
    allow(service).to receive(:set_article_read).with('article-1', read: true).and_return(snapshot)

    workflow.set_article_read('article-1', read: true)

    expect(menu_session_store.load.rss_selected_article_id).to eq('article-1')
    expect(menu_transient_store.load.rss_message).to eq('Marked as read')
  end

  describe 'asynchronous operation' do
    let(:deferred_executor) do
      executor = Object.new
      executor.instance_variable_set(:@jobs, [])
      executor.define_singleton_method(:submit) { |&job| @jobs << job }
      executor.define_singleton_method(:run_all) { @jobs.shift.call until @jobs.empty? }
      executor
    end
    let(:relay) { Shoko::Application::Services::AsyncResultRelay.new(async_executor: deferred_executor) }

    subject(:workflow) do
      described_class.new(
        rss_reader_service: service,
        menu_session_store: menu_session_store,
        menu_transient_store: menu_transient_store,
        async_relay: relay
      )
    end

    it 'shows the syncing status immediately; the snapshot lands on drain' do
      allow(service).to receive(:sync_all).and_return(snapshot: snapshot, errors: [], checked: 1, added: 2)

      workflow.sync_feeds

      expect(menu_transient_store.load.rss_status).to eq(:syncing)
      expect(workflow.network_pending?).to be(true)

      deferred_executor.run_all
      workflow.process_pending_events

      expect(menu_transient_store.load.rss_status).to eq(:ready)
      expect(menu_transient_store.load.rss_feeds).to eq(feeds)
      expect(workflow.network_pending?).to be(false)
    end
  end
end
