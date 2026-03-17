# frozen_string_literal: true

module MenuScreenRenderHelpers
  ANSI_RE = /\e\[[0-9;?]*[A-Za-z]/.freeze

  def render_component(component, width:, height:)
    terminal = Shoko::TestSupport::TerminalDouble
    terminal.reset!
    surface = Shoko::Adapters::Ui::Components::Surface.new(terminal)
    bounds = Shoko::Adapters::Ui::Components::Rect.new(x: 1, y: 1, width: width, height: height)
    component.render(surface, bounds)
    terminal.writes
  end

  def rendered_text(writes)
    writes.map { |entry| strip_ansi(entry[:text]) }.join("\n")
  end

  def row_text(writes, row)
    writes
      .select { |entry| entry[:row] == row }
      .sort_by { |entry| entry[:col] }
      .map { |entry| strip_ansi(entry[:text]) }
      .join
  end

  def strip_ansi(text)
    text.to_s.gsub(ANSI_RE, '')
  end

  def with_color_mode(mode)
    Shoko::Adapters::Ui::Constants::Ui.apply_color_mode(mode)
    yield
  ensure
    Shoko::Adapters::Ui::Constants::Ui.apply_color_mode(:dark)
  end

  class NullObserverRegistry
    def add_observer(*); end
  end
end
