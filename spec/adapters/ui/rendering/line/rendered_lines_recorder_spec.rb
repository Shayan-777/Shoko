# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Ui::Components::Reading::RenderedLinesRecorder do
  let(:buffer) { {} }
  let(:runtime_config_class) do
    Class.new do
      include Shoko::Application::Ports::Outbound::RuntimeConfig

      def debug_geometry_enabled? = false
    end
  end
  let(:runtime_config) { runtime_config_class.new }
  let(:dependencies) { instance_double('RenderDependencies', runtime_config: runtime_config, logger: nil) }
  let(:recorder) { described_class.new(buffer: buffer, dependencies: dependencies) }

  it 'records link spans and chapter source path for display lines with links' do
    cells = %w[a b c].each_with_index.map do |cluster, index|
      Shoko::Adapters::Ui::Rendering::Models::LineCell.new(
        cluster: cluster,
        char_start: index,
        char_end: index + 1,
        display_width: 1,
        screen_x: index
      )
    end
    geometry = Shoko::Adapters::Ui::Rendering::Models::LineGeometry.new(
      page_id: 0,
      column_id: 0,
      row: 5,
      column_origin: 4,
      line_offset: 19,
      plain_text: 'abc',
      styled_text: 'abc',
      cells: cells
    )
    line = Shoko::Application::Ports::Outbound::Formatting::DisplayLine.new(
      text: 'abc',
      segments: [
        Shoko::Core::Models::TextSegment.new(text: 'a', styles: {}),
        Shoko::Core::Models::TextSegment.new(text: 'b', styles: { link: '#note1' }),
        Shoko::Core::Models::TextSegment.new(text: 'c', styles: {}),
      ],
      metadata: { chapter_source_path: 'OPS/ch1.xhtml' }
    )

    recorder.record(geometry, line: line)

    entry = buffer.fetch(geometry.key)
    expect(entry[:link_spans]).to eq([{ start_char: 1, end_char: 2, href: '#note1' }])
    expect(entry[:chapter_source_path]).to eq('OPS/ch1.xhtml')
  end
end
