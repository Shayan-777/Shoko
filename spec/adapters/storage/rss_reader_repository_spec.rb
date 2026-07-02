# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Storage::RssReaderRepository do
  let(:feed) do
    Shoko::Core::Models::RssFeed.new(
      id: 'feed-1',
      url: 'https://example.com/feed.xml',
      title: 'Example Feed',
      added_at: '2026-04-06T08:00:00Z'
    )
  end
  let(:article) do
    Shoko::Core::Models::RssArticle.new(
      id: 'article-1',
      feed_id: 'feed-1',
      title: 'Example Article',
      summary: 'Summary',
      content: 'Content',
      url: 'https://example.com/article',
      published_at: '2026-04-06T07:00:00Z'
    )
  end

  around do |example|
    Dir.mktmpdir do |dir|
      @file_path = File.join(dir, 'rss_reader.json')
      example.run
    end
  end

  subject(:repository) do
    described_class.new(
      file_path: @file_path,
      atomic_file_writer: Shoko::Adapters::Storage::AtomicFileWriter
    )
  end

  it 'returns a blank snapshot when the file does not exist' do
    expect(repository.load).to eq(schema_version: 1, feeds: [], articles: [])
  end

  it 'round-trips feeds and articles through disk storage' do
    repository.save(feeds: [feed], articles: [article])
    snapshot = repository.load

    expect(snapshot[:feeds]).to eq([feed])
    expect(snapshot[:articles]).to eq([article])
  end

  it 'supports update blocks against the current stored snapshot' do
    repository.save(feeds: [feed], articles: [])

    snapshot = repository.update do |current|
      current.merge(articles: [article])
    end

    expect(snapshot[:feeds]).to eq([feed])
    expect(snapshot[:articles]).to eq([article])
    expect(repository.load[:articles]).to eq([article])
  end

  it 'degrades to a blank snapshot and quarantines the file for invalid on-disk payloads' do
    File.write(@file_path, JSON.dump(schema_version: 999, feeds: [], articles: []))

    expect(repository.load).to eq(schema_version: 1, feeds: [], articles: [])
    expect(File.exist?(@file_path)).to be(false)
    expect(Dir.glob("#{@file_path}.corrupt-*").length).to eq(1)
  end

  it 'degrades to a blank snapshot and quarantines the file for corrupt JSON' do
    File.write(@file_path, '{ not json')

    expect(repository.load).to eq(schema_version: 1, feeds: [], articles: [])
    expect(Dir.glob("#{@file_path}.corrupt-*").length).to eq(1)
  end

  it 'recovers after quarantine: the next save starts a fresh store' do
    File.write(@file_path, '{ not json')
    repository.load

    repository.save(feeds: [feed], articles: [article])

    expect(repository.load[:feeds]).to eq([feed])
    expect(Dir.glob("#{@file_path}.corrupt-*").length).to eq(1)
  end

  it 'serializes concurrent update blocks so no read-modify-write is lost' do
    repository.save(feeds: [feed], articles: [])
    barrier = Queue.new

    slow = Thread.new do
      repository.update do |current|
        barrier.pop
        current.merge(articles: current[:articles] + [article])
      end
    end

    fast = Thread.new do
      barrier << :go
      repository.update do |current|
        current.merge(articles: current[:articles] + [article.with(id: 'article-2')])
      end
    end

    [slow, fast].each(&:join)

    expect(repository.load[:articles].map(&:id)).to contain_exactly('article-1', 'article-2')
  end
end
