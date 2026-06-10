# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Ui::Components::Screens::StartupNoticeComponent do
  let(:bounds) { Shoko::Adapters::Ui::Components::Rect.new(1, 1, 80, 24) }

  def recording_surface(writes)
    surface = Object.new
    surface.define_singleton_method(:write) do |_bounds, row, col, text|
      writes << { row: row, col: col, text: text }
    end
    surface
  end

  def reader_with_notice(value)
    reader = Object.new
    reader.define_singleton_method(:startup_notice) { value }
    reader
  end

  it 'renders the notice on the bottom row when one is present' do
    writes = []
    component = described_class.new(menu_state_reader: reader_with_notice('Settings were reset to defaults'))

    component.render(recording_surface(writes), bounds)

    expect(writes.length).to eq(1)
    expect(writes.first[:row]).to eq(bounds.height)
    expect(writes.first[:text]).to include('Settings were reset to defaults')
  end

  it 'renders nothing when the notice is nil or blank' do
    [nil, '', '   '].each do |value|
      writes = []
      component = described_class.new(menu_state_reader: reader_with_notice(value))

      component.render(recording_surface(writes), bounds)

      expect(writes).to be_empty
    end
  end

  it 'renders nothing when the reader does not expose startup_notice' do
    writes = []
    component = described_class.new(menu_state_reader: Object.new)

    component.render(recording_surface(writes), bounds)

    expect(writes).to be_empty
  end

  it 'truncates the notice to the available width' do
    writes = []
    narrow = Shoko::Adapters::Ui::Components::Rect.new(1, 1, 20, 5)
    component = described_class.new(menu_state_reader: reader_with_notice('A' * 100))

    component.render(recording_surface(writes), narrow)

    visible = Shoko::Shared::Terminal::TextMetrics.visible_length(writes.first[:text])
    expect(visible).to be <= 20
  end
end
