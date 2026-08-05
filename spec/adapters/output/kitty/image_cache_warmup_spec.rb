# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'

RSpec.describe Shoko::Adapters::Output::Kitty::ImageCacheWarmup do
  def build_progress_collector
    Struct.new(:events) do
      def update_status(message: nil, progress: nil)
        events << { message: message, progress: progress }
      end
    end.new([])
  end

  let(:renderer_class) do
    Struct.new(:calls) do
      def renderable_source?(src)
        src.to_s.end_with?('.png', '.jpg', '.jpeg')
      end

      def warm_cache(**kwargs)
        calls << kwargs
        kwargs[:src].include?('cached') ? :cached : :warmed
      end
    end
  end

  let(:renderer) { renderer_class.new([]) }
  let(:service) { described_class.new(kitty_image_renderer: renderer) }
  let(:epub_file) do
    Tempfile.new(['image-cache-warmup', '.epub']).tap do |file|
      file.write('test archive placeholder')
      file.flush
    end
  end

  after { epub_file.close! }

  it 'extracts renderable EPUB image sources from chapter raw content' do
    chapter = Shoko::Core::Models::Chapter.new(
      number: '1',
      title: 'Chapter 1',
      lines: [],
      metadata: { source_path: 'OPS/ch1.xhtml' },
      blocks: nil,
      raw_content: <<~HTML
        <html><body>
          <img src="../images/a.png" alt="a" />
          <p>Ignore SVG placeholder</p>
          <img src="../images/cached.jpg" />
          <img src="../images/a.png" />
          <img src="../images/vector.svg" />
        </body></html>
      HTML
    )
    document = Struct.new(:chapters, :cache_sha, :canonical_path).new(
      [chapter],
      'a' * 64,
      epub_file.path
    )

    result = service.warm_document(document)

    expect(result.status).to eq(:warmed)
    expect(result.warmed).to eq(1)
    expect(result.cached).to eq(1)
    expect(renderer.calls).to eq(
      [
        {
          book_sha: 'a' * 64,
          epub_path: document.canonical_path,
          chapter_entry_path: 'OPS/ch1.xhtml',
          src: '../images/a.png',
        },
        {
          book_sha: 'a' * 64,
          epub_path: document.canonical_path,
          chapter_entry_path: 'OPS/ch1.xhtml',
          src: '../images/cached.jpg',
        },
      ]
    )
  end

  it 'skips non-epub documents' do
    document = Struct.new(:chapters, :cache_sha, :canonical_path).new([], 'a' * 64, __FILE__)

    result = service.warm_document(document)

    expect(result.status).to eq(:skipped)
    expect(renderer.calls).to be_empty
  end

  it 'reports progress while warming renderable image resources' do
    collector = build_progress_collector
    chapter = Shoko::Core::Models::Chapter.new(
      number: '1',
      title: 'Chapter 1',
      lines: [],
      metadata: { source_path: 'OPS/ch1.xhtml' },
      blocks: nil,
      raw_content: <<~HTML
        <html><body>
          <img src="../images/a.png" alt="a" />
          <img src="../images/cached.jpg" />
        </body></html>
      HTML
    )
    document = Struct.new(:chapters, :cache_sha, :canonical_path).new(
      [chapter],
      'a' * 64,
      epub_file.path
    )

    result = service.warm_document(document, progress_reporter: collector)

    expect(result.status).to eq(:warmed)
    expect(collector.events).to eq(
      [
        { message: 'Caching inline images (1/2)...', progress: 0.0 },
        { message: 'Caching inline images (2/2)...', progress: 0.5 },
        { message: 'Caching inline images...', progress: 1.0 },
      ]
    )
  end
end
