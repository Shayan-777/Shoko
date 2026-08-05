# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Ui::Components::Screens::RssReaderScreenComponent do
  include MenuScreenRenderHelpers

  let(:menu_state_reader) do
    instance_double(
      Shoko::Adapters::Runtime::SessionState::MenuSnapshotProjectionAdapter,
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
      rss_selection: nil,
      rss_context_menu: nil,
      rss_find_query: '',
      rss_find_cursor: 0,
      rss_find_active: false,
      rss_find_index: 0,
      rss_annotations: [],
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
      rss_open_article: nil,
      rss_status: :ready,
      rss_message: 'Synced 2 feeds, 2 unread',
      rss_last_synced_at: '2026-04-06T08:00:00Z'
    )
  end
  let(:dependencies) { instance_double(Shoko::Adapters::Ui::MenuUiDependencies, menu_state_reader: menu_state_reader, menu_hit_registry: nil) }
  let(:component) { described_class.new(menu_state_reader: menu_state_reader) }

  def text_for(mode:, width:, height:)
    writes = with_color_mode(mode) { render_component(component, width: width, height: height) }
    rendered_text(writes)
  end

  [
    [:dark, 80, 24],
    [:light, 120, 32]
  ].each do |mode, width, height|
    it "renders the article blocks on the canvas in #{mode} mode at #{width}x#{height}" do
      text = text_for(mode: mode, width: width, height: height)

      expect(text).to include('RSS Reader')
      expect(text).to include('Morning Edition')
      expect(text).to include('Daily Planet')
      expect(text).not_to include('│')
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

  it 'renders the lazily loaded body without changing the RSS reading view' do
    allow(menu_state_reader).to receive_messages(
      rss_focus: :content,
      rss_open_article: menu_state_reader.rss_articles.first.merge(
        content: 'The asynchronously loaded full article body.'
      )
    )

    expect(text_for(mode: :dark, width: 100, height: 28))
      .to include('The asynchronously loaded full article body.')
  end

  it 'renders the reading view in zen mode' do
    allow(menu_state_reader).to receive(:rss_zen_mode).and_return(true)

    text = text_for(mode: :dark, width: 100, height: 28)

    expect(text).to include('Morning Edition')
    expect(text).to include('City hall story with more detail.')
  end

  it 'keeps the list visible and points at the status bar in add-feed mode' do
    allow(menu_state_reader).to receive_messages(
      mode: :rss_reader_feed_input,
      rss_feed_input: 'https://example.com/feed.xml',
      rss_feed_input_cursor: 28
    )

    text = text_for(mode: :dark, width: 90, height: 28)

    expect(text).to include('type in the bar below')
    expect(text).to include('Morning Edition')
  end
  describe 'the reading view scrollbar' do
    let(:width) { 90 }
    let(:height) { 28 }
    let(:menu_design) { Shoko::Adapters::Ui::Components::MenuDesign }
    let(:palette) { Shoko::Adapters::Ui::Components::StatusBar::Palette }
    # The frame itself says where its content ends, so the spec cannot drift
    # from the canvas insets.
    let(:bar_col) do
      bounds = Shoko::Adapters::Ui::Components::Rect.new(x: 1, y: 1, width: width, height: height)
      frame = menu_design::CanvasFrame.new(nil, bounds)
      frame.content_x + frame.content_width - 1
    end

    def long_article(paragraphs)
      body = (1..paragraphs).map { |i| "<p>Absatz #{i}. #{'Wort ' * 40}</p>" }.join
      blocks = Shoko::Adapters::Rss::ArticleBlockParser.new.parse(body)
      [{
        id: 'article-1', feed_id: 'feed-1', feed_title: 'Daily Planet', title: 'Morning Edition',
        author: 'Clark', summary: 'City hall story', content: 'City hall story.',
        content_blocks: blocks, url: 'https://example.com/story',
        published_label: '2026-04-06 08:00', read: false, starred: true,
      }]
    end

    def writes_for(articles)
      allow(menu_state_reader).to receive(:rss_articles).and_return(articles)
      allow(menu_state_reader).to receive(:rss_focus).and_return(:content)
      render_component(component, width: width, height: height)
    end

    def grid_for(articles)
      rendered_grid(writes_for(articles), width: width, height: height)
    end

    # Every scrollbar row carries the glyph; only the thumb rows carry the
    # thumb colour, so the moving part is found by colour, not by shape.
    def thumb_rows(writes)
      writes.select do |entry|
        entry[:col] == bar_col && entry[:text].include?(palette::LIST_SCROLL_THUMB_FG)
      end.map { |entry| entry[:row] }
    end

    def bar_rows(grid)
      (1..height).select { |row| grid[row][bar_col - 1] == menu_design::CanvasScrollbar::GLYPH }
    end

    it 'appears when the article is longer than the pane' do
      expect(bar_rows(grid_for(long_article(20)))).not_to be_empty
    end

    it 'stays away when the whole article already fits' do
      expect(bar_rows(grid_for(long_article(1)))).to be_empty
    end

    # The badge is a full-width line; before the window reserved a row for it,
    # it covered the last line of prose and the foot of the scrollbar.
    it 'does not let the position badge cover prose or the scrollbar' do
      grid = grid_for(long_article(20))
      badge_row = height - 2

      expect(grid[badge_row]).to match(/\d+-\d+ \/ \d+/)
      expect(bar_rows(grid)).not_to include(badge_row)
      expect(grid[badge_row - 1][bar_col - 1]).to eq(menu_design::CanvasScrollbar::GLYPH)
    end

    it 'never lets prose run into the scrollbar column or its gap' do
      grid = grid_for(long_article(20))
      gap = described_class::READING_RIGHT_GAP

      bar_rows(grid).each do |row|
        expect(grid[row][(bar_col - gap - 1)..(bar_col - 2)].strip).to eq('')
      end
    end

    it 'draws a track over the whole pane and a thumb within it' do
      articles = long_article(20)
      writes = writes_for(articles)

      expect(thumb_rows(writes)).not_to be_empty
      expect(thumb_rows(writes).length).to be < bar_rows(grid_for(articles)).length
    end

    it 'moves the thumb down as the article is scrolled' do
      articles = long_article(20)
      at_top = thumb_rows(writes_for(articles))
      allow(menu_state_reader).to receive(:rss_content_scroll).and_return(10_000)
      at_bottom = thumb_rows(writes_for(articles))

      expect(at_bottom.first).to be > at_top.first
      expect(at_bottom.last).to eq(bar_rows(grid_for(articles)).last)
    end
  end

  # Laying an article out costs milliseconds; scrolling must not pay it again.
  describe 'reading layout reuse' do
    let(:article) do
      { id: 'a1', title: 'T', content: 'body text', summary: 's', content_blocks: [],
        feed_title: 'F', author: nil, published_label: 'now', url: 'https://x.de/a' }
    end

    it 'reuses the laid-out lines while the article and measure are unchanged' do
      first = component.send(:reading_lines, article, 60)

      expect(component).not_to receive(:build_reading_lines)
      expect(component.send(:reading_lines, article, 60)).to equal(first)
    end

    it 're-lays out when the measure changes' do
      component.send(:reading_lines, article, 60)

      expect(component.send(:reading_lines, article, 40)).not_to equal(component.send(:reading_lines, article, 60))
    end

    it 're-lays out when the article changes' do
      first = component.send(:reading_lines, article, 60)
      other = article.merge(id: 'a2')

      expect(component.send(:reading_lines, other, 60)).not_to equal(first)
    end

    it 're-lays out when the same article gains content on a re-sync' do
      first = component.send(:reading_lines, article, 60)
      hydrated = article.merge(content: 'body text with much more detail after hydration')

      expect(component.send(:reading_lines, hydrated, 60)).not_to equal(first)
    end
  end
  # The pane maps a terminal position to a character in the article and back;
  # every text action depends on that mapping being exact.
  describe 'reading-pane text geometry' do
    let(:width) { 60 }
    let(:height) { 22 }
    let(:bounds) { Shoko::Adapters::Ui::Components::Rect.new(x: 1, y: 1, width: width, height: height) }

    def article_with(html)
      blocks = Shoko::Adapters::Rss::ArticleBlockParser.new.parse(html)
      [{ id: 'article-1', feed_id: 'feed-1', feed_title: 'Daily Planet', title: 'Morning Edition',
         author: 'Clark', summary: 'excerpt', content: 'plain', content_blocks: blocks,
         url: 'https://example.com/story', published_label: '2026-04-06 08:00',
         read: false, starred: false }]
    end

    def open_article(html)
      allow(menu_state_reader).to receive_messages(rss_articles: article_with(html), rss_focus: :content)
      render_component(component, width: width, height: height)
      component
    end

    def grid(html)
      allow(menu_state_reader).to receive_messages(rss_articles: article_with(html), rss_focus: :content)
      rendered_grid(render_component(component, width: width, height: height), width: width, height: height)
    end

    def position_of(html, needle)
      rows = grid(html)
      row = (1..height).find { |r| rows[r].include?(needle) }
      [rows[row].index(needle) + 1, row]
    end

    it 'resolves a click to the character under it' do
      html = '<p>Erster Absatz hier.</p>'
      screen = open_article(html)
      column, row = position_of(html, 'Absatz')

      index = screen.reading_hit(column, row, bounds)

      expect(screen.reading_selection_text({ start_index: index, end_index: index + 6 }, bounds)).to eq('Absatz')
    end

    it 'resolves a drag across a row to the text between the two points' do
      html = '<p>Erster Absatz hier.</p>'
      screen = open_article(html)
      column, row = position_of(html, 'Absatz')

      selection = screen.reading_selection_from_points(
        start_column: column, start_row: row, end_column: column + 5, end_row: row, bounds: bounds
      )

      expect(screen.reading_selection_text(selection, bounds)).to eq('Absatz')
    end

    it 'keeps the character under both endpoints when dragging backwards' do
      html = '<p>Erster Absatz hier.</p>'
      screen = open_article(html)
      column, row = position_of(html, 'Absatz')

      selection = screen.reading_selection_from_points(
        start_column: column + 5, start_row: row, end_column: column, end_row: row, bounds: bounds
      )

      expect(screen.reading_selection_text(selection, bounds)).to eq('Absatz')
    end

    it 'is nil off the prose' do
      screen = open_article('<p>Text.</p>')

      expect(screen.reading_hit(2, height - 1, bounds)).to be_nil
    end

    # Clicking a bullet or a quote gutter must land on the words, not the decoration.
    it 'clamps a click on a list marker to the start of the item text' do
      html = '<ul><li>Ein Punkt</li></ul>'
      screen = open_article(html)
      bullet_column, row = position_of(html, '•')
      text_column, = position_of(html, 'Ein Punkt')

      expect(screen.reading_hit(bullet_column, row, bounds))
        .to eq(screen.reading_hit(text_column, row, bounds))
    end

    it 'picks out the word under a position' do
      html = '<p>Erster Absatz hier.</p>'
      screen = open_article(html)
      column, row = position_of(html, 'Absatz')
      index = screen.reading_hit(column + 2, row, bounds)

      word = screen.reading_word_at(index, bounds)

      expect(screen.reading_selection_text(word, bounds)).to eq('Absatz')
    end

    it 'stores the selection with its text and surrounding context' do
      html = '<p>Erster Absatz hier.</p>'
      screen = open_article(html)
      column, row = position_of(html, 'Absatz')
      index = screen.reading_hit(column, row, bounds)

      payload = screen.reading_selection_payload({ start_index: index, end_index: index + 6 }, bounds)

      expect(payload[:text]).to eq('Absatz')
      expect(payload[:prefix]).to end_with('Erster ')
      expect(payload[:suffix]).to start_with(' hier.')
    end

    it 'refuses a selection that is only whitespace' do
      screen = open_article('<p>a b</p>')

      expect(screen.reading_selection_payload({ start_index: 0, end_index: 0 }, bounds)).to be_nil
    end

    it 'reports the pane inactive when no article is open' do
      allow(menu_state_reader).to receive_messages(rss_articles: [], rss_focus: :content)

      expect(component.reading_pane_active?).to be(false)
    end
  end

  describe 'selection and find highlighting' do
    let(:width) { 60 }
    let(:height) { 22 }
    let(:highlighter) { Shoko::Adapters::Ui::Components::Screens::ReadingSpanHighlighter }

    def article_rows
      [{ id: 'article-1', feed_id: 'feed-1', feed_title: 'F', title: 'T', author: nil,
         summary: 's', content: 'Die Drohne kam. Eine zweite Drohne folgte.',
         content_blocks: [], url: 'https://example.com/s', published_label: 'now',
         read: false, starred: false }]
    end

    def writes_with(**overrides)
      allow(menu_state_reader).to receive_messages(
        { rss_articles: article_rows, rss_focus: :content }.merge(overrides)
      )
      render_component(component, width: width, height: height)
    end

    def row_containing(writes, needle)
      writes.find { |entry| strip_ansi(entry[:text]).include?(needle) }
    end

    def selection_of(needle)
      allow(menu_state_reader).to receive_messages(rss_articles: article_rows, rss_focus: :content,
                                                   rss_selection: nil, rss_find_query: '')
      bounds = Shoko::Adapters::Ui::Components::Rect.new(x: 1, y: 1, width: width, height: height)
      render_component(component, width: width, height: height)
      geometry = component.send(:reading_geometry, bounds)
      at = component.send(:reading_stream, geometry[:lines]).index(needle)
      { start_index: at, end_index: at + needle.length, text: needle }
    end

    it 'reverses the selected span only' do
      writes = writes_with(rss_selection: selection_of('Drohne'))

      expect(row_containing(writes, 'Drohne')[:text]).to include(highlighter::SELECTION)
    end

    it 'draws nothing specially when there is no selection' do
      writes = writes_with(rss_selection: nil)

      expect(row_containing(writes, 'Drohne')[:text]).not_to include(highlighter::SELECTION)
    end

    it 'underlines find matches and marks the current one' do
      writes = writes_with(rss_find_query: 'drohne', rss_find_active: true, rss_find_index: 0)
      row = row_containing(writes, 'Drohne')[:text]

      expect(row).to include(highlighter::MATCH)
      expect(row).to include(Shoko::Shared::Terminal::Ansi::REVERSE)
    end

    it 'shows the match counter in the status line' do
      writes = writes_with(rss_find_query: 'drohne', rss_find_active: true, rss_find_index: 0)

      expect(rendered_text(writes)).to include('find: drohne').and include('1/2')
    end

    it 'marks where a saved note was made' do
      writes = writes_with(rss_annotations: [{ quote: 'Drohne', note: 'check' }])

      expect(row_containing(writes, 'Drohne')[:text]).to include(highlighter::ANNOTATION)
    end

    it 'ignores a note whose quote is no longer in the article' do
      writes = writes_with(rss_annotations: [{ quote: 'nicht vorhanden', note: '' }])

      expect(row_containing(writes, 'Drohne')[:text]).not_to include(highlighter::ANNOTATION)
    end

    it 'says so when the query matches nothing' do
      writes = writes_with(rss_find_query: 'zebra', rss_find_active: true, rss_find_index: 0)

      expect(rendered_text(writes)).to include('no matches')
    end
  end

  describe 'the selection actions menu' do
    let(:width) { 60 }
    let(:height) { 22 }
    let(:bounds) { Shoko::Adapters::Ui::Components::Rect.new(x: 1, y: 1, width: width, height: height) }

    def open_menu(anchor_column: 10, anchor_row: 8)
      allow(menu_state_reader).to receive_messages(
        rss_focus: :content,
        rss_selection: { start_index: 0, end_index: 5, text: 'quote' },
        rss_context_menu: { anchor_column: anchor_column, anchor_row: anchor_row }
      )
      render_component(component, width: width, height: height)
    end

    it 'offers the same actions the book reader offers over a selection' do
      expect(rendered_text(open_menu)).to include('Copy').and include('Look Up')
                                                          .and include('Translate').and include('Annotate')
    end

    it 'resolves a click on a row to that action' do
      open_menu(anchor_column: 10, anchor_row: 8)

      expect(component.context_menu_hit(11, 9, bounds)[:intent]).to eq(:rss_reader_lookup_selection)
    end

    it 'resolves a click outside the card to nothing' do
      open_menu(anchor_column: 10, anchor_row: 8)

      expect(component.context_menu_hit(1, 20, bounds)).to be_nil
    end

    it 'keeps the card inside the pane when opened near the edge' do
      writes = open_menu(anchor_column: width - 1, anchor_row: height - 1)
      rows = rendered_grid(writes, width: width, height: height)

      expect(rows.compact.join).to include('Annotate')
    end
  end
end
