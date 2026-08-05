# frozen_string_literal: true

require 'spec_helper'
require 'json'

RSpec.describe 'Storage codecs' do
  it 'round-trips bookmarks through the stable legacy disk shape' do
    codec = Shoko::Adapters::Storage::Codecs::BookmarkCodec
    bookmark = Shoko::Core::Models::Bookmark.new(
      chapter_index: 2, line_offset: 8, text_snippet: 'A line',
      created_at: Time.utc(2026, 8, 5, 10, 30), anchor: { 'quote' => 'A line' }
    )

    payload = JSON.parse(JSON.generate(codec.dump(bookmark)))

    expect(payload.keys).to contain_exactly('chapter', 'line_offset', 'text', 'timestamp', 'anchor')
    expect(codec.load(payload)).to eq(bookmark)
  end

  it 'round-trips reading progress without leaking the persisted chapter key into the model' do
    codec = Shoko::Adapters::Storage::Codecs::ReadingProgressCodec
    progress = Shoko::Core::Models::ReadingProgress.new(
      chapter_index: 4, line_offset: 12, timestamp: '2026-08-05T10:30:00Z'
    )

    payload = JSON.parse(JSON.generate(codec.dump(progress)))

    expect(payload).to include('chapter' => 4)
    expect(payload).not_to have_key('chapter_index')
    expect(codec.load(payload)).to eq(progress)
  end

  it 'round-trips typed RSS blocks through JSON only at the storage boundary' do
    codec = Shoko::Adapters::Storage::Codecs::RssCodec
    block = Shoko::Core::Models::ContentBlock.new(
      type: :paragraph,
      segments: [Shoko::Core::Models::TextSegment.new(text: 'Body', styles: { italic: true })]
    )
    article = Shoko::Core::Models::RssArticle.new(
      id: 'article', feed_id: 'feed', title: 'Title', content_blocks: [block]
    )

    payload = JSON.parse(JSON.generate(codec.dump_article(article)))
    restored = codec.load_article(payload)

    expect(restored).to eq(article)
    expect(restored.content_blocks.first).to be_a(Shoko::Core::Models::ContentBlock)
  end
end
