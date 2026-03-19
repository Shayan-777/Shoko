# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::Controllers::Sidebar::AnchorResolver do
  let(:document) { instance_double('Document') }
  let(:document_reader) { -> { document } }
  let(:formatting_service) { instance_double('FormattingService') }
  let(:layout_service) do
    instance_double(
      'LayoutService',
      effective_content_width: 80,
      calculate_metrics: [80, 20],
      adjust_for_line_spacing: 20
    )
  end
  let(:config_reader) { instance_double('ConfigReader', view_mode: :single, line_spacing: :normal) }
  let(:sidebar_state_reader) { instance_double('SidebarStateReader', sidebar_visible?: false) }
  let(:resolver) do
    described_class.new(
      document_reader: document_reader,
      formatting_service: formatting_service,
      layout_service: layout_service,
      ui_state_reader: nil,
      config_reader: config_reader,
      sidebar_state_reader: sidebar_state_reader
    )
  end

  it 'prefers a strict numeric line match when multiple lines share the same anchor metadata' do
    lines = [
      Shoko::Core::Models::DisplayLine.new(
        text: '35. another footnote',
        segments: [],
        metadata: { anchors: %w[fn3 fn35] }
      ),
      Shoko::Core::Models::DisplayLine.new(
        text: '3. target footnote',
        segments: [],
        metadata: { anchors: %w[fn3 fn35] }
      ),
    ]
    allow(formatting_service).to receive(:wrap_all).and_return(lines)

    offset = resolver.line_offset_for_href(href: '#fn3', chapter_index: 0)

    expect(offset).to eq(1)
  end

  it 'matches superscript footnote numbers when resolving ambiguous anchor metadata' do
    lines = [
      Shoko::Core::Models::DisplayLine.new(
        text: '³⁵. another footnote',
        segments: [],
        metadata: { anchors: %w[fn3 fn35] }
      ),
      Shoko::Core::Models::DisplayLine.new(
        text: '³. target footnote',
        segments: [],
        metadata: { anchors: %w[fn3 fn35] }
      ),
    ]
    allow(formatting_service).to receive(:wrap_all).and_return(lines)

    offset = resolver.line_offset_for_href(href: '#fn3', chapter_index: 0)

    expect(offset).to eq(1)
  end

  it 'returns nil for ambiguous numeric anchors without a confident line match' do
    lines = [
      Shoko::Core::Models::DisplayLine.new(
        text: 'introduction',
        segments: [],
        metadata: { anchors: %w[fn3 fn35] }
      ),
      Shoko::Core::Models::DisplayLine.new(
        text: 'continuation',
        segments: [],
        metadata: { anchors: %w[fn3 fn35] }
      ),
    ]
    allow(formatting_service).to receive(:wrap_all).and_return(lines)

    offset = resolver.line_offset_for_href(href: '#fn3', chapter_index: 0)

    expect(offset).to be_nil
  end

  it 'resolves anchor offsets against the active terminal width rather than fallback width' do
    line_for_three_80 = Shoko::Core::Models::DisplayLine.new(
      text: '3. target footnote',
      segments: [],
      metadata: { anchors: ['front_fn3'] }
    )
    line_for_three_137 = Shoko::Core::Models::DisplayLine.new(
      text: '3. target footnote',
      segments: [],
      metadata: { anchors: ['front_fn3'] }
    )
    line_for_thirty_five = Shoko::Core::Models::DisplayLine.new(
      text: '35. unrelated footnote',
      segments: [],
      metadata: {}
    )

    lines_80 = Array.new(286) { Shoko::Core::Models::DisplayLine.new(text: '', segments: [], metadata: {}) }
    lines_137 = Array.new(286) { Shoko::Core::Models::DisplayLine.new(text: '', segments: [], metadata: {}) }
    lines_80[285] = line_for_three_80
    lines_137[181] = line_for_three_137
    lines_137[285] = line_for_thirty_five

    dynamic_formatting_service = instance_double('FormattingService')
    allow(dynamic_formatting_service).to receive(:wrap_all) do |_doc, _chapter_index, width, config:, lines_per_page:|
      case width
      when 137 then lines_137
      else lines_80
      end
    end

    dynamic_layout_service = instance_double('LayoutService')
    allow(dynamic_layout_service).to receive(:effective_content_width) do |width, sidebar_visible:|
      width
    end
    allow(dynamic_layout_service).to receive(:calculate_metrics) do |width, _height, _view_mode|
      [width, 20]
    end
    allow(dynamic_layout_service).to receive(:adjust_for_line_spacing).and_return(20)

    ui_state = instance_double('UiStateReader', terminal_width: 137, terminal_height: 40)
    resolver_with_ui = described_class.new(
      document_reader: document_reader,
      formatting_service: dynamic_formatting_service,
      layout_service: dynamic_layout_service,
      ui_state_reader: ui_state,
      config_reader: config_reader,
      sidebar_state_reader: sidebar_state_reader
    )

    offset = resolver_with_ui.line_offset_for_href(href: '#front_fn3', chapter_index: 0)

    expect(offset).to eq(181)
  end
end
