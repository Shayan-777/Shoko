# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Ui::Components::MenuDesign::MasterDetailShell do
  include MenuScreenRenderHelpers

  def build_shell(width:, height:)
    terminal = Shoko::TestSupport::TerminalDouble
    terminal.reset!
    surface = Shoko::Adapters::Ui::Components::Surface.new(terminal)
    bounds = Shoko::Adapters::Ui::Components::Rect.new(x: 1, y: 1, width: width, height: height)
    [described_class.new(surface, bounds), terminal]
  end

  it 'builds a side-by-side inspector layout on standard terminals' do
    shell, = build_shell(width: 80, height: 24)
    layout = shell.build_layout(prelude_rows: 2, detail_visible: true)

    expect(layout.wide_split).to be(true)
    expect(layout.stacked_detail).to be(false)
    expect(layout.secondary_panel).not_to be_nil
    expect(layout.primary_panel.frame.width).to be < layout.shell_width
  end

  it 'stacks the inspector when width is tight' do
    shell, = build_shell(width: 58, height: 20)
    layout = shell.build_layout(detail_visible: true, min_primary_width: 34, min_detail_width: 26)

    expect(layout.wide_split).to be(false)
    expect(layout.stacked_detail).to be(true)
    expect(layout.secondary_panel.frame.y).to be > layout.primary_panel.frame.y
  end

  it 'renders panel headings into the shared shell chrome' do
    shell, terminal = build_shell(width: 80, height: 24)
    layout = shell.build_layout(detail_visible: true)

    shell.render_panels(layout: layout, primary_title: 'Results', secondary_title: 'Selection')

    expect(row_text(terminal.writes, layout.primary_panel.frame.y)).to include('RESULTS')
    expect(row_text(terminal.writes, layout.secondary_panel.frame.y)).to include('SELECTION')
  end
end
