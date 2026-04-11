# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Rss::ArticleContentFetcher do
  it 'extracts substantially more content from Jeff Geerling linked posts than the RSS excerpt',
     :requires_live_rss do
    feed_fetcher = Shoko::Adapters::Rss::FeedFetcher.new
    article_fetcher = described_class.new

    feed = feed_fetcher.fetch('https://www.jeffgeerling.com/blog.xml')
    article = feed[:articles].find do |entry|
      entry[:url].to_s.include?('/build-your-own-dial-up-isp-with-a-raspberry-pi/')
    end || feed[:articles].first

    excerpt = article[:content].to_s.strip.empty? ? article[:summary].to_s : article[:content].to_s
    full_content = article_fetcher.fetch(article[:url])

    expect(full_content.length).to be > excerpt.length + 500
    expect(full_content).to include('What better way to do it than through Wi-Fi?')
  end
end
