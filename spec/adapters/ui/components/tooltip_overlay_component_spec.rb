# frozen_string_literal: true

require 'spec_helper'
require 'shoko/application/services/annotations/anchor_resolver'

RSpec.describe Shoko::Adapters::Ui::Components::TooltipOverlayComponent do
  def strip_ansi(text)
    text.to_s.gsub(%r{\e\[[0-9;]*[ -/]*[@-~]}, '')
  end

  def build_geometry_entry(row:, text:, column_origin:, line_offset:, page_id: 0, column_id: 0)
    cells = text.each_char.with_index.map do |char, index|
      Shoko::Adapters::Ui::Rendering::Models::LineCell.new(
        cluster: char,
        char_start: index,
        char_end: index + 1,
        display_width: 1,
        screen_x: index
      )
    end

    geometry = Shoko::Adapters::Ui::Rendering::Models::LineGeometry.new(
      page_id: page_id,
      column_id: column_id,
      row: row,
      column_origin: column_origin,
      line_offset: line_offset,
      plain_text: text,
      styled_text: text,
      cells: cells
    )

    { geometry.key => { geometry: geometry } }
  end

  let(:terminal) { Shoko::TestSupport::TerminalDouble }
  let(:surface) { Shoko::Adapters::Ui::Components::Surface.new(terminal) }
  let(:bounds) { Shoko::Adapters::Ui::Components::Rect.new(x: 1, y: 1, width: 120, height: 40) }
  let(:coordinate_service) { double('CoordinateService') }
  let(:rendered_content_reader) { instance_double('RenderedContentReader', rendered_lines: {}) }

  before do
    terminal.reset!
  end

  it 'renders a prominent landing highlight for a wrapped search result match' do
    highlight = {
      chapter_index: 2,
      line_index: 11,
      page_index: 17,
      before: 'political and ',
      match_text: 'economic',
      after: ' order',
    }
    reader_state_reader = instance_double(
      'ReaderStateReader',
      annotations: [],
      current_chapter: 2,
      current_page_index: 17,
      search_landing_highlight: highlight,
      selection: nil,
      popup_menu: nil,
      annotations_overlay: nil,
      annotation_editor_overlay: nil,
      dictionary_popup: nil,
      dictionary_lookup_popup: nil,
      in_book_search_popup: nil,
      toc_lookup_popup: nil,
      translator_lookup_popup: nil,
      notes_lookup_popup: nil,
      message: nil
    )
    rendered_lines = build_geometry_entry(row: 8, text: 'political and eco', column_origin: 4, line_offset: 11)
                     .merge(build_geometry_entry(row: 9, text: 'nomic order', column_origin: 4, line_offset: 11))

    component = described_class.new(
      coordinate_service: coordinate_service,
      reader_state_reader: reader_state_reader,
      rendered_content_reader: rendered_content_reader
    )
    allow(rendered_content_reader).to receive(:rendered_lines).and_return(rendered_lines)

    component.render(surface, bounds)

    highlighted = terminal.writes.select do |write|
      write[:text].include?(Shoko::Adapters::Ui::Constants::Ui::SEARCH_HIGHLIGHT_BG)
    end

    expect(highlighted.length).to eq(2)
    expect(strip_ansi(highlighted.map { |write| write[:text] }.join)).to include('economic')
    expect(highlighted.all? { |write| write[:text].include?(Shoko::Adapters::Ui::Constants::Ui::SEARCH_HIGHLIGHT_FG) }).to be(true)
  end

  it 'uses search-result context to highlight the selected occurrence when a line has repeated matches' do
    highlight = {
      chapter_index: 2,
      line_index: 9,
      page_index: 17,
      before: 'freedom and ',
      match_text: 'power',
      after: ' again',
    }
    line = 'power and freedom and power again'
    reader_state_reader = instance_double(
      'ReaderStateReader',
      annotations: [],
      current_chapter: 2,
      current_page_index: 17,
      search_landing_highlight: highlight,
      selection: nil,
      popup_menu: nil,
      annotations_overlay: nil,
      annotation_editor_overlay: nil,
      dictionary_popup: nil,
      dictionary_lookup_popup: nil,
      in_book_search_popup: nil,
      toc_lookup_popup: nil,
      translator_lookup_popup: nil,
      notes_lookup_popup: nil,
      message: nil
    )
    rendered_lines = build_geometry_entry(row: 10, text: line, column_origin: 3, line_offset: 9)

    component = described_class.new(
      coordinate_service: coordinate_service,
      reader_state_reader: reader_state_reader,
      rendered_content_reader: rendered_content_reader
    )
    allow(rendered_content_reader).to receive(:rendered_lines).and_return(rendered_lines)

    component.render(surface, bounds)

    highlighted = terminal.writes.select do |write|
      write[:text].include?(Shoko::Adapters::Ui::Constants::Ui::SEARCH_HIGHLIGHT_BG)
    end
    second_match_col = 3 + line.index('power', 1)

    expect(highlighted.length).to eq(1)
    expect(highlighted.first[:col]).to eq(second_match_col)
    expect(strip_ansi(highlighted.first[:text])).to eq('power')
  end

  it 'still highlights the landed match when saved page or line hints are stale' do
    highlight = {
      chapter_index: 2,
      line_index: 999,
      page_index: 3,
      before: 'then the ',
      match_text: 'dialectic',
      after: ' returned',
    }
    reader_state_reader = instance_double(
      'ReaderStateReader',
      annotations: [],
      current_chapter: 2,
      current_page_index: 17,
      search_landing_highlight: highlight,
      selection: nil,
      popup_menu: nil,
      annotations_overlay: nil,
      annotation_editor_overlay: nil,
      dictionary_popup: nil,
      dictionary_lookup_popup: nil,
      in_book_search_popup: nil,
      toc_lookup_popup: nil,
      translator_lookup_popup: nil,
      notes_lookup_popup: nil,
      message: nil
    )
    rendered_lines = build_geometry_entry(row: 6, text: 'introductory material', column_origin: 2, line_offset: 41)
                     .merge(build_geometry_entry(row: 7, text: 'then the dialectic returned at once', column_origin: 2,
                                                 line_offset: 42))

    component = described_class.new(
      coordinate_service: coordinate_service,
      reader_state_reader: reader_state_reader,
      rendered_content_reader: rendered_content_reader
    )
    allow(rendered_content_reader).to receive(:rendered_lines).and_return(rendered_lines)

    component.render(surface, bounds)

    highlighted = terminal.writes.select do |write|
      write[:text].include?(Shoko::Adapters::Ui::Constants::Ui::SEARCH_HIGHLIGHT_BG)
    end

    expect(highlighted.length).to eq(1)
    expect(strip_ansi(highlighted.first[:text])).to eq('dialectic')
  end

  it 'normalizes string-key landing highlights before matching rendered geometry' do
    highlight = {
      'chapter_index' => 2,
      'line_index' => 11,
      'page_index' => 17,
      'before' => 'political and ',
      'match_text' => 'economic',
      'after' => ' order',
    }
    reader_state_reader = instance_double(
      'ReaderStateReader',
      annotations: [],
      current_chapter: 2,
      current_page_index: 17,
      search_landing_highlight: highlight,
      selection: nil,
      popup_menu: nil,
      annotations_overlay: nil,
      annotation_editor_overlay: nil,
      dictionary_popup: nil,
      dictionary_lookup_popup: nil,
      in_book_search_popup: nil,
      toc_lookup_popup: nil,
      translator_lookup_popup: nil,
      notes_lookup_popup: nil,
      message: nil
    )
    rendered_lines = build_geometry_entry(row: 8, text: 'political and eco', column_origin: 4, line_offset: 11)
                     .merge(build_geometry_entry(row: 9, text: 'nomic order', column_origin: 4, line_offset: 11))

    component = described_class.new(
      coordinate_service: coordinate_service,
      reader_state_reader: reader_state_reader,
      rendered_content_reader: rendered_content_reader
    )
    allow(rendered_content_reader).to receive(:rendered_lines).and_return(rendered_lines)

    component.render(surface, bounds)

    highlighted = terminal.writes.select do |write|
      write[:text].include?(Shoko::Adapters::Ui::Constants::Ui::SEARCH_HIGHLIGHT_BG)
    end

    expect(highlighted.length).to eq(2)
    expect(strip_ansi(highlighted.map { |write| write[:text] }.join)).to include('economic')
  end

  it 'does not render an expired landing highlight' do
    highlight = {
      chapter_index: 2,
      line_index: 11,
      expires_at: 101.0,
      match_text: 'economic',
    }
    reader_state_reader = instance_double(
      'ReaderStateReader',
      annotations: [],
      current_chapter: 2,
      current_page_index: 17,
      search_landing_highlight: highlight,
      selection: nil,
      popup_menu: nil,
      annotations_overlay: nil,
      annotation_editor_overlay: nil,
      dictionary_popup: nil,
      dictionary_lookup_popup: nil,
      in_book_search_popup: nil,
      toc_lookup_popup: nil,
      translator_lookup_popup: nil,
      notes_lookup_popup: nil,
      message: nil
    )
    rendered_lines = build_geometry_entry(row: 8, text: 'political and economic order', column_origin: 4, line_offset: 11)

    component = described_class.new(
      coordinate_service: coordinate_service,
      reader_state_reader: reader_state_reader,
      rendered_content_reader: rendered_content_reader
    )
    allow(component).to receive(:monotonic_now).and_return(101.0)
    allow(rendered_content_reader).to receive(:rendered_lines).and_return(rendered_lines)

    component.render(surface, bounds)

    highlighted = terminal.writes.select do |write|
      write[:text].include?(Shoko::Adapters::Ui::Constants::Ui::SEARCH_HIGHLIGHT_BG)
    end

    expect(highlighted).to be_empty
  end

  it 'does not pick an arbitrary occurrence when the selected result cannot be uniquely identified' do
    highlight = {
      chapter_index: 2,
      line_index: 7,
      match_text: 'power',
    }
    line = 'power and freedom and power again'
    reader_state_reader = instance_double(
      'ReaderStateReader',
      annotations: [],
      current_chapter: 2,
      current_page_index: 17,
      search_landing_highlight: highlight,
      selection: nil,
      popup_menu: nil,
      annotations_overlay: nil,
      annotation_editor_overlay: nil,
      dictionary_popup: nil,
      dictionary_lookup_popup: nil,
      in_book_search_popup: nil,
      toc_lookup_popup: nil,
      translator_lookup_popup: nil,
      notes_lookup_popup: nil,
      message: nil
    )
    rendered_lines = build_geometry_entry(row: 10, text: line, column_origin: 3, line_offset: 7)

    component = described_class.new(
      coordinate_service: coordinate_service,
      reader_state_reader: reader_state_reader,
      rendered_content_reader: rendered_content_reader
    )
    allow(rendered_content_reader).to receive(:rendered_lines).and_return(rendered_lines)

    component.render(surface, bounds)

    highlighted = terminal.writes.select do |write|
      write[:text].include?(Shoko::Adapters::Ui::Constants::Ui::SEARCH_HIGHLIGHT_BG)
    end

    expect(highlighted).to be_empty
  end

  describe 'landing highlight blink' do
    def landing_writes(started_offset)
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      highlight = {
        chapter_index: 2, line_index: 11, page_index: 17,
        before: 'political and ', match_text: 'economic', after: ' order',
        started_at: now - started_offset, expires_at: now + 10
      }
      reader = instance_double(
        'ReaderStateReader',
        annotations: [], current_chapter: 2, current_page_index: 17,
        search_landing_highlight: highlight, selection: nil, popup_menu: nil,
        annotations_overlay: nil, annotation_editor_overlay: nil,
        dictionary_popup: nil, dictionary_lookup_popup: nil, in_book_search_popup: nil,
        toc_lookup_popup: nil, translator_lookup_popup: nil, notes_lookup_popup: nil, message: nil
      )
      lines = build_geometry_entry(row: 8, text: 'political and eco', column_origin: 4, line_offset: 11)
              .merge(build_geometry_entry(row: 9, text: 'nomic order', column_origin: 4, line_offset: 11))
      allow(rendered_content_reader).to receive(:rendered_lines).and_return(lines)

      described_class.new(coordinate_service: coordinate_service, reader_state_reader: reader,
                          rendered_content_reader: rendered_content_reader).render(surface, bounds)
      terminal.writes.select { |write| write[:text].include?(Shoko::Adapters::Ui::Constants::Ui::SEARCH_HIGHLIGHT_BG) }
    end

    it 'paints the orange background during an on-pulse' do
      expect(landing_writes(0.0)).not_to be_empty
    end

    it 'goes dark during the off-pulse between the two blinks' do
      # 0.60s elapsed falls in the gap between the first and second pulse.
      expect(landing_writes(0.60)).to be_empty
    end
  end

  describe 'saved annotation highlights' do
    def reader_with_annotation(annotation)
      instance_double(
        'ReaderStateReader',
        annotations: [annotation], current_chapter: 2, current_page_index: 0,
        search_landing_highlight: nil, selection: nil, popup_menu: nil,
        annotations_overlay: nil, annotation_editor_overlay: nil,
        dictionary_popup: nil, dictionary_lookup_popup: nil, in_book_search_popup: nil,
        toc_lookup_popup: nil, translator_lookup_popup: nil, notes_lookup_popup: nil, message: nil
      )
    end

    def resolution_for(line_offset:, start_char:, end_char:, line_text:)
      resolver_module = Shoko::Application::Services::Annotations::AnchorResolver
      span = resolver_module::LineSpan.new(
        line_offset: line_offset, start_char: start_char, end_char: end_char, line_text: line_text
      )
      resolver_module::Resolution.new(start_line_offset: line_offset, line_spans: [span])
    end

    let(:saved_bg) { Shoko::Adapters::Ui::Constants::Ui::HIGHLIGHT_BG_SAVED }

    it 'resolves the anchor against the current layout and paints the located span' do
      annotation = { 'chapter_index' => 2, 'anchor' => { 'quote' => 'economic' } }
      reader = reader_with_annotation(annotation)
      anchor_resolver = instance_double(Shoko::Application::Services::Annotations::AnchorResolver)
      allow(anchor_resolver).to receive(:resolve).and_return(
        resolution_for(line_offset: 11, start_char: 0, end_char: 8, line_text: 'economic order')
      )
      rendered_lines = build_geometry_entry(row: 9, text: 'economic order', column_origin: 4, line_offset: 11)
      allow(rendered_content_reader).to receive(:rendered_lines).and_return(rendered_lines)

      described_class.new(
        coordinate_service: coordinate_service, reader_state_reader: reader,
        rendered_content_reader: rendered_content_reader, anchor_resolver: anchor_resolver
      ).render(surface, bounds)

      expect(anchor_resolver).to have_received(:resolve).with(
        an_instance_of(Shoko::Core::Models::DocumentAnchor), chapter_index: 2
      )
      saved = terminal.writes.select { |write| write[:text].include?(saved_bg) }
      expect(strip_ansi(saved.map { |write| write[:text] }.join)).to eq('economic')
    end

    it 'skips annotations from other chapters and those without an anchor' do
      reader = instance_double(
        'ReaderStateReader',
        annotations: [
          { 'chapter_index' => 5, 'anchor' => { 'quote' => 'elsewhere' } },
          { 'chapter_index' => 2, 'anchor' => {} },
        ],
        current_chapter: 2, current_page_index: 0,
        search_landing_highlight: nil, selection: nil, popup_menu: nil,
        annotations_overlay: nil, annotation_editor_overlay: nil,
        dictionary_popup: nil, dictionary_lookup_popup: nil, in_book_search_popup: nil,
        toc_lookup_popup: nil, translator_lookup_popup: nil, notes_lookup_popup: nil, message: nil
      )
      anchor_resolver = instance_double(Shoko::Application::Services::Annotations::AnchorResolver)
      rendered_lines = build_geometry_entry(row: 9, text: 'economic order', column_origin: 4, line_offset: 11)
      allow(rendered_content_reader).to receive(:rendered_lines).and_return(rendered_lines)

      described_class.new(
        coordinate_service: coordinate_service, reader_state_reader: reader,
        rendered_content_reader: rendered_content_reader, anchor_resolver: anchor_resolver
      ).render(surface, bounds)

      expect(anchor_resolver).not_to have_received(:resolve) if anchor_resolver.respond_to?(:resolve)
      expect(terminal.writes.select { |write| write[:text].include?(saved_bg) }).to be_empty
    end

    it 'renders nothing when no anchor resolver is wired' do
      annotation = { 'chapter_index' => 2, 'anchor' => { 'quote' => 'economic' } }
      reader = reader_with_annotation(annotation)
      rendered_lines = build_geometry_entry(row: 9, text: 'economic order', column_origin: 4, line_offset: 11)
      allow(rendered_content_reader).to receive(:rendered_lines).and_return(rendered_lines)

      described_class.new(
        coordinate_service: coordinate_service, reader_state_reader: reader,
        rendered_content_reader: rendered_content_reader
      ).render(surface, bounds)

      expect(terminal.writes.select { |write| write[:text].include?(saved_bg) }).to be_empty
    end
  end
end
