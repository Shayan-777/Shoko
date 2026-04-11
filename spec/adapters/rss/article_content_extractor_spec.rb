# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Rss::ArticleContentExtractor do
  subject(:extractor) { described_class.new }

  it 'extracts the article body from a Jeff Geerling style section container' do
    html = <<~HTML
      <!doctype html>
      <html>
        <body>
          <main>
            <article>
              <div class="post-container">
                <div class="post-content">
                  <div class="title">
                    <h1 class="title">Build your own Dial-up ISP with a Raspberry Pi</h1>
                    <div class="meta">Apr 3, 2026</div>
                  </div>
                  <section class="body">
                    <p>Intro paragraph from the feed excerpt.</p>
                    <p>This paragraph only exists on the linked article page.</p>
                    <div class="yt-embed"><iframe src="https://www.youtube.com/embed/demo"></iframe></div>
                    <p>Another later paragraph with the real post body.</p>
                  </section>
                </div>
              </div>
            </article>
          </main>
        </body>
      </html>
    HTML

    text = extractor.extract(html)

    expect(text).to include('Intro paragraph from the feed excerpt.')
    expect(text).to include('This paragraph only exists on the linked article page.')
    expect(text).to include('Another later paragraph with the real post body.')
    expect(text).not_to include('Apr 3, 2026')
  end

  it 'falls back to article content when no named body container exists' do
    html = <<~HTML
      <html>
        <body>
          <article>
            <h1>Title</h1>
            <p>Paragraph one.</p>
            <p>Paragraph two.</p>
          </article>
        </body>
      </html>
    HTML

    text = extractor.extract(html)

    expect(text).to include('Title')
    expect(text).to include('Paragraph one.')
    expect(text).to include('Paragraph two.')
  end
end
