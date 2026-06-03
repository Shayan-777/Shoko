# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Ui::Components::StatusBarComponent do
  let(:terminal) { Shoko::TestSupport::TerminalDouble }
  let(:surface) { Shoko::Adapters::Ui::Components::Surface.new(terminal) }
  let(:bounds) { Shoko::Adapters::Ui::Components::Rect.new(x: 1, y: 1, width: 90, height: 1) }

  before { terminal.reset! }

  def visible_width(text)
    Shoko::Shared::Terminal::TextMetrics.visible_length(text)
  end

  def reader_context
    ns = Shoko::Adapters::Ui::Components::StatusBar
    ns::StatusContext.build(
      badge: ns::FormatBadge.for_format(:epub),
      title: 'The Great Gatsby',
      details: ['Ch 3/12', 'The Valley of Ashes'],
      trailing: ['42 / 318'],
      progress: 0.13,
      progress_rgb: [63, 185, 80]
    )
  end

  it 'paints a single full-width row carrying badge, title, page count and percent' do
    context = reader_context
    described_class.new(-> { context }).render(surface, bounds)

    text = terminal.writes.last[:text]
    expect(visible_width(text)).to eq(90)
    expect(text).to include('EPUB')
    expect(text).to include('The Great Gatsby')
    expect(text).to include('42 / 318')
    expect(text).to include('13%')
  end

  it 'reserves one row when there is a context to show' do
    expect(described_class.new(-> { reader_context }).preferred_height(24)).to eq(1)
  end

  it 'collapses to zero height and draws nothing when the context is absent' do
    component = described_class.new(-> {})
    expect(component.preferred_height(24)).to eq(0)
    component.render(surface, bounds)
    expect(terminal.writes).to be_empty
  end

  it 'renders the query with a caret as a search input' do
    ns = Shoko::Adapters::Ui::Components::StatusBar
    context = ns::StatusContext.build(
      badge: ns::FormatBadge.mode_badge('Search', :epub),
      title: 'whale',
      placeholder: 'type to search…',
      caret: true,
      trailing: ['1 / 2']
    )
    described_class.new(-> { context }).render(surface, bounds)

    text = terminal.writes.last[:text]
    plain = Shoko::Shared::Terminal::TextMetrics.strip_ansi(text)
    expect(plain).to include('Search')
    expect(plain).to include('epub')
    expect(plain).to include('whale')
    expect(text).to include(ns::Palette::CARET)
    expect(text).to include(ns::Palette::BADGE_SLANT)
  end

  it 'shows the placeholder with a caret when the query is empty' do
    ns = Shoko::Adapters::Ui::Components::StatusBar
    context = ns::StatusContext.build(badge: ns::FormatBadge.mode_badge('Search', :epub),
                                      title: '', placeholder: 'type to search…', caret: true)
    described_class.new(-> { context }).render(surface, bounds)

    expect(Shoko::Shared::Terminal::TextMetrics.strip_ansi(terminal.writes.last[:text])).to include('type to search…')
  end

  it 'omits the progress bar on narrow terminals but keeps the percentage' do
    narrow = Shoko::Adapters::Ui::Components::Rect.new(x: 1, y: 1, width: 40, height: 1)
    described_class.new(-> { reader_context }).render(surface, narrow)

    text = terminal.writes.last[:text]
    expect(visible_width(text)).to eq(40)
    expect(text).to include('13%')
  end
end
