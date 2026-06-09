# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Ui::Components::Screens::RssReaderScreenComponent do
  include MenuScreenRenderHelpers

  let(:menu_state_reader) do
    instance_double(
      'MenuStateReader',
      mode: :rss_reader,
      rss_focus: :articles,
      rss_scope: :all,
      rss_selected_feed_key: 'feed-1',
      rss_selected_article_id: 'article-1',
      rss_content_scroll: 0,
      rss_feed_input: '',
      rss_feed_input_cursor: 0,
      rss_filter_query: '',
      rss_filter_cursor: 0,
      rss_zen_mode: false,
      rss_feeds: [
        { key: '__all__', title: 'All Feeds', count: 3, unread_count: 2, sync_error: nil },
        { key: 'feed-1', title: 'Daily Planet', count: 3, unread_count: 2, sync_error: nil }
      ],
      rss_articles: [
        {
          id: 'article-1',
          feed_id: 'feed-1',
          feed_title: 'Daily Planet',
          title: 'Morning Edition',
          author: 'Clark',
          summary: 'City hall story',
          content: 'City hall story with more detail.',
          url: 'https://example.com/story',
          published_label: '2026-04-06 08:00',
          read: false,
          starred: true
        }
      ],
      rss_status: :ready,
      rss_message: 'Synced 2 feeds, 2 unread',
      rss_last_synced_at: '2026-04-06T08:00:00Z'
    )
  end
  let(:dependencies) { instance_double('Dependencies', menu_state_reader: menu_state_reader) }
  let(:component) { described_class.new(dependencies: dependencies) }

  def text_for(mode:, width:, height:)
    writes = with_color_mode(mode) { render_component(component, width: width, height: height) }
    rendered_text(writes)
  end

  [
    [:dark, 80, 24],
    [:light, 120, 32]
  ].each do |mode, width, height|
    it "renders the article list in the shared shell in #{mode} mode at #{width}x#{height}" do
      text = text_for(mode: mode, width: width, height: height)

      expect(text).to include('SHOKO')
      expect(text).to include('RSS Reader')
      expect(text).to include('Morning Edition')
      expect(text).to include('Daily Planet')
    end
  end

  it 'shows the feeds list when focused on feeds' do
    allow(menu_state_reader).to receive(:rss_focus).and_return(:feeds)

    text = text_for(mode: :dark, width: 90, height: 28)

    expect(text).to include('Feeds')
    expect(text).to include('Daily Planet')
  end

  it 'renders a spacious reading view when an article is opened' do
    allow(menu_state_reader).to receive(:rss_focus).and_return(:content)

    text = text_for(mode: :dark, width: 100, height: 28)

    expect(text).to include('Morning Edition')
    expect(text).to include('City hall story with more detail.')
  end

  it 'renders the reading view in zen mode' do
    allow(menu_state_reader).to receive(:rss_zen_mode).and_return(true)

    text = text_for(mode: :dark, width: 100, height: 28)

    expect(text).to include('Morning Edition')
    expect(text).to include('City hall story with more detail.')
  end

  it 'renders the centered field in add-feed mode' do
    allow(menu_state_reader).to receive_messages(
      mode: :rss_reader_feed_input,
      rss_feed_input: 'https://example.com/feed.xml',
      rss_feed_input_cursor: 28
    )

    text = text_for(mode: :dark, width: 90, height: 28)

    expect(text).to include('Add Feed')
    expect(text).to include('Paste an RSS or Atom feed URL')
    expect(text).to include('https://example.com/feed.xml')
  end
end
