# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::UseCases::Menu::Actions::RssReader do
  let(:menu_session_store_class) do
    Class.new do
      include Shoko::Application::Ports::Outbound::MenuSessionStore

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
  end

  let(:menu_transient_store_class) do
    Class.new do
      include Shoko::Application::Ports::Outbound::MenuTransientStore

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
  end

  let(:menu_session_store) do
    menu_session_store_class.new(
      Shoko::Application::Ports::Outbound::State::MenuSessionSnapshot.build(
        mode: :rss_reader,
        rss_focus: :feeds,
        rss_scope: :all,
        rss_selected_feed_key: 'feed-1',
        rss_selected_article_id: 'article-1',
        rss_content_scroll: 0,
        rss_feed_input: '',
        rss_feed_input_cursor: 0,
        rss_filter_query: '',
        rss_filter_cursor: 0,
        rss_zen_mode: false
      )
    )
  end
  let(:menu_transient_store) do
    menu_transient_store_class.new(
      Shoko::Application::Ports::Outbound::State::MenuTransientSnapshot.build(
        rss_feeds: [
          { key: '__all__', title: 'All Feeds', count: 4, unread_count: 2, sync_error: nil },
          { key: 'feed-1', title: 'Feed One', count: 2, unread_count: 1, sync_error: nil },
          { key: 'feed-2', title: 'Feed Two', count: 2, unread_count: 1, sync_error: nil }
        ],
        rss_articles: [
          { id: 'article-1', title: 'Alpha', read: false, starred: false, published_label: '2026-04-06 09:00' },
          { id: 'article-2', title: 'Beta', read: true, starred: false, published_label: '2026-04-05 08:00' }
        ],
        rss_status: :ready,
        rss_message: 'Ready'
      )
    )
  end
  let(:rss_reader_workflow) do
    instance_double(
      'MenuStateController',
      refresh_rss_reader: nil,
      sync_rss_feeds: nil,
      set_rss_article_read: nil,
      set_rss_article_starred: nil,
      remove_rss_feed: nil,
      add_rss_feed: nil
    )
  end

  subject(:action) do
    described_class.new(
      menu_session_store: menu_session_store,
      rss_reader_workflow: rss_reader_workflow,
      menu_transient_store: menu_transient_store
    )
  end

  it 'moves between feeds by refreshing the projection with the next feed key' do
    payload = Shoko::Application::UseCases::Requests::SelectionDelta.new(delta: 1)

    action.call(:rss_reader_move_down, payload)

    expect(rss_reader_workflow).to have_received(:refresh_rss_reader).with(
      preferred_feed_key: 'feed-2',
      preferred_article_id: nil,
      reset_content: true
    )
  end

  it 'moves the selected article inside the articles pane' do
    menu_session_store.save(menu_session_store.load.with(rss_focus: :articles))
    payload = Shoko::Application::UseCases::Requests::SelectionDelta.new(delta: 1)

    action.call(:rss_reader_move_down, payload)

    expect(menu_session_store.load.rss_selected_article_id).to eq('article-2')
    expect(menu_session_store.load.rss_content_scroll).to eq(0)
  end

  it 'updates the filter query live and refreshes the reader projection' do
    menu_session_store.save(menu_session_store.load.with(mode: :rss_reader_filter, rss_filter_query: 'alp', rss_filter_cursor: 3))
    payload = Shoko::Application::UseCases::Requests::EditOp.new(operation: :insert, text: 'h')

    action.call(:edit_rss_filter, payload)

    expect(menu_session_store.load.rss_filter_query).to eq('alph')
    expect(menu_session_store.load.rss_filter_cursor).to eq(4)
    expect(rss_reader_workflow).to have_received(:refresh_rss_reader).with(reset_content: true)
  end

  it 'submits a new feed URL and returns to the reader mode' do
    menu_session_store.save(
      menu_session_store.load.with(
        mode: :rss_reader_feed_input,
        rss_feed_input: 'https://example.com/feed.xml',
        rss_feed_input_cursor: 28
      )
    )

    action.call(:rss_reader_submit_add_feed)

    expect(rss_reader_workflow).to have_received(:add_rss_feed).with('https://example.com/feed.xml')
    expect(menu_session_store.load.mode).to eq(:rss_reader)
    expect(menu_session_store.load.rss_feed_input).to eq('')
  end

  it 'delegates article starring to the rss reader workflow' do
    menu_session_store.save(menu_session_store.load.with(rss_focus: :articles))

    action.call(:rss_reader_mark_starred)

    expect(rss_reader_workflow).to have_received(:set_rss_article_starred).with('article-1', starred: true)
  end

  it 'switches zen mode into content focus so directional movement scrolls the article body' do
    payload = Shoko::Application::UseCases::Requests::SelectionDelta.new(delta: 1)

    action.call(:rss_reader_toggle_zen)
    action.call(:rss_reader_move_down, payload)

    expect(menu_session_store.load.rss_zen_mode).to be(true)
    expect(menu_session_store.load.rss_focus).to eq(:content)
    expect(menu_session_store.load.rss_selected_article_id).to eq('article-1')
    expect(menu_session_store.load.rss_content_scroll).to eq(1)
  end

  it 'removes the currently selected feed through the rss workflow' do
    action.call(:rss_reader_remove_feed)

    expect(rss_reader_workflow).to have_received(:remove_rss_feed).with('feed-1')
  end
end
