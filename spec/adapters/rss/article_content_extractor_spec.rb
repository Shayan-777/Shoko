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

    text = extractor.extract(html).text

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

    text = extractor.extract(html).text

    expect(text).to include('Title')
    expect(text).to include('Paragraph one.')
    expect(text).to include('Paragraph two.')
  end

  it 'drops navigation, header, and footer chrome when falling back to the body' do
    html = <<~HTML
      <html>
        <body>
          <header><a href="/">Get Gentoo!</a></header>
          <nav class="navbar"><ul><li>Wiki</li><li>Bugs</li><li>Forums</li></ul></nav>
          <div id="content">
            <h1>Copy Fail kernel vulnerabilities</h1>
            <p>The Linux kernel has been facing privilege escalation vulnerabilities.</p>
          </div>
          <footer><div class="sitemap">Planet Archives Devmanual Gitweb Infra status</div></footer>
        </body>
      </html>
    HTML

    text = extractor.extract(html).text

    expect(text).to include('Copy Fail kernel vulnerabilities')
    expect(text).to include('The Linux kernel has been facing privilege escalation vulnerabilities.')
    expect(text).not_to include('Get Gentoo!')
    expect(text).not_to include('Wiki')
    expect(text).not_to include('Infra status')
  end
end
