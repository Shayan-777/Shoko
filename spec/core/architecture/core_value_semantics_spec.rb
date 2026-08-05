# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Core value semantics' do
  VALUE_TYPES = [
    Shoko::Core::Models::BookData,
    Shoko::Core::Models::Bookmark,
    Shoko::Core::Models::BookmarkData,
    Shoko::Core::Models::Chapter,
    Shoko::Core::Models::ContentBlock,
    Shoko::Core::Models::ReadingProgress,
    Shoko::Core::Models::RssArticle,
    Shoko::Core::Models::RssFeed,
    Shoko::Core::Models::TextSegment,
    Shoko::Core::Models::TOCEntry,
    Shoko::Core::Services::InBookSearchService::SearchMatch,
    Shoko::Core::Services::InBookSearchService::SearchResult,
    Shoko::Core::Services::InBookSearchService::SearchableLine,
  ].freeze

  it 'uses immutable Data classes consistently for core transport values' do
    expect(VALUE_TYPES).to all(be < Data)
  end

  it 'copies and freezes nested data without taking ownership of caller values' do
    title = +'A title'
    metadata = { nested: { labels: [+'draft'] } }
    chapter = Shoko::Core::Models::Chapter.new(
      number: 1, title: title, lines: [+'line'], metadata: metadata
    )

    expect(chapter).to be_frozen
    expect(chapter.title).to be_frozen
    expect(chapter.lines).to be_frozen
    expect(chapter.metadata.dig(:nested, :labels).first).to be_frozen
    expect(title).not_to be_frozen
    expect(metadata.dig(:nested, :labels).first).not_to be_frozen
  end

  it 'keeps persistence-specific codecs out of core value sources' do
    root = File.expand_path('../../..', __dir__)
    files = %w[bookmark reading_progress rss_feed rss_article].map do |name|
      File.join(root, 'lib', 'shoko', 'core', 'models', "#{name}.rb")
    end
    persistence_methods = /^\s*def (?:self\.)?(?:from_h|to_h)\b/

    expect(files.select { |path| File.read(path).match?(persistence_methods) }).to be_empty
  end
end
