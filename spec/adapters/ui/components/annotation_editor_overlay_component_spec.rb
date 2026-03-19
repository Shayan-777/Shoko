# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Ui::Components::AnnotationEditorOverlayComponent do
  def strip_ansi(text)
    text.to_s.gsub(%r{\e\[[0-9;]*[ -/]*[@-~]}, '')
  end

  def build_geometry_row(row:, text:, column_origin: 1, page_id: 0, column_id: 0, line_offset: 0)
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

  subject(:component) do
    described_class.new(
      selected_text: 'Quoted text',
      range: { start: 0, length: 10 },
      chapter_index: 0
    )
  end

  let(:terminal) { Shoko::TestSupport::TerminalDouble }
  let(:surface) { Shoko::Adapters::Ui::Components::Surface.new(terminal) }
  let(:bounds) { Shoko::Adapters::Ui::Components::Rect.new(x: 1, y: 1, width: 120, height: 40) }

  before do
    terminal.reset!
  end

  describe '#render and click handling' do
    it 'renders footer controls and maps click regions to save/cancel actions' do
      component.render(surface, bounds)
      regions = component.instance_variable_get(:@button_regions)

      save = regions.fetch(:save)
      cancel = regions.fetch(:cancel)

      expect(component.handle_click(save[:col], save[:row])).to eq(type: :save, note: '')
      expect(component.handle_click(cancel[:col], cancel[:row])).to eq(type: :cancel)
    end

    it 'uses the tooltip glass palette for panel and quote styling' do
      component.render(surface, bounds)

      rendered = terminal.writes.map { |write| write[:text] }.join("\n")
      ui = Shoko::Adapters::Ui::Constants::Ui

      expect(rendered).to include(ui::TOOLTIP_BG_DEFAULT)
      expect(rendered).to include(ui::TOOLTIP_BG_SELECTED)
      expect(rendered).to include(ui::TOOLTIP_FG_DEFAULT)
      expect(rendered).to include(ui::TOOLTIP_FG_SELECTED)
      expect(rendered).to include(ui::TOOLTIP_GLASS_FG_DEFAULT)
    end

    it 'blends backdrop glyphs into empty annotation rows for translucency' do
      layout = component.send(:overlay_layout, bounds)
      backdrop_text = ('translucent ' * 24).strip
      rendered_lines = {}
      (layout.origin_y..(layout.origin_y + layout.height - 1)).each do |row|
        rendered_lines.merge!(build_geometry_row(row: row, text: backdrop_text, line_offset: row))
      end
      component.update_rendered_lines(rendered_lines)

      component.render(surface, bounds)

      rendered = terminal.writes.map { |write| write[:text] }.join("\n")
      plain = strip_ansi(rendered)

      sample = component.send(:backdrop_segment, layout.origin_y, layout.origin_x, 50)
      expect(sample).to include('translucent')
      expect(plain).to include('Annotation')
    end

    it 'uses reduced-visibility backdrop tint in light mode as well' do
      component.update_color_mode(:light)
      layout = component.send(:overlay_layout, bounds)
      rendered_lines = {}
      (layout.origin_y..(layout.origin_y + layout.height - 1)).each do |row|
        rendered_lines.merge!(build_geometry_row(row: row, text: ('light backdrop ' * 20).strip, line_offset: row))
      end
      component.update_rendered_lines(rendered_lines)

      component.render(surface, bounds)

      rendered = terminal.writes.map { |write| write[:text] }.join("\n")
      expect(rendered).to include(described_class::PANEL_BG_LIGHT)
      expect(rendered).to include(described_class::PANEL_FG_LIGHT)
      expect(rendered).to include(described_class::QUOTE_BG_LIGHT)
      expect(rendered).to include(described_class::BACKDROP_FG_LIGHT)
    end
  end

  describe '#handle_key' do
    it 'supports save and cancel shortcuts' do
      cancel_key = Shoko::Shared::KeyDefinitions::ACTIONS[:cancel].first

      expect(component.handle_key("\x13")).to eq(type: :save, note: '')
      expect(component.handle_key(cancel_key)).to eq(type: :cancel)
    end

    it 'edits note content via printable, newline, and backspace keys' do
      expect(component.note).to eq('')

      component.handle_key('a')
      component.handle_key("\n")
      component.handle_key('b')
      component.handle_key("\x7F")

      expect(component.note).to eq("a\n")
    end
  end

  describe 'spell suggestions' do
    subject(:component_with_note) do
      described_class.new(
        selected_text: 'Quoted text',
        range: { start: 0, length: 10 },
        chapter_index: 0,
        annotation: { note: 'This is ambigues' }
      )
    end

    it 'replaces the current word with the selected dictionary suggestion' do
      target = component_with_note.spellcheck_target
      component_with_note.show_spell_suggestions(target, %w[ambiguity ambiguous])

      component_with_note.handle_move_down
      component_with_note.handle_enter

      expect(target).to eq(word: 'ambigues', start: 8, end: 16)
      expect(component_with_note.note).to eq('This is ambiguous')
    end

    it 'renders a compact completion-style spell suggestion popup beside the current word' do
      target = component_with_note.spellcheck_target
      component_with_note.show_spell_suggestions(target, ['ambiguous'], scope_key: 'lang:en', scope_label: 'English')

      component_with_note.render(surface, bounds)

      rendered = terminal.writes.map { |write| write[:text] }.join("\n")
      plain = strip_ansi(rendered)
      expect(plain).to include('abc')
      expect(plain).to include('English')
      expect(plain).to include('ambiguous')
    end

    it 'exposes spell suggestion popup scope state for controller-side cycling' do
      target = component_with_note.spellcheck_target
      component_with_note.show_spell_suggestions(target, ['ambiguous'], scope_key: 'lang:en', scope_label: 'English')

      expect(component_with_note.spell_suggestion_state).to eq(
        word: 'ambigues',
        start: 8,
        end: 16,
        scope_key: 'lang:en',
        scope_label: 'English',
        can_cycle: false
      )
    end

    it 'keeps a scope popup open even when that scope has no suggestions' do
      target = component_with_note.spellcheck_target
      component_with_note.show_spell_suggestions(target, [], scope_key: 'lang:de', scope_label: 'German', can_cycle: true)

      component_with_note.render(surface, bounds)

      rendered = terminal.writes.map { |write| write[:text] }.join("\n")
      plain = strip_ansi(rendered)
      expect(plain).to include('German')
      expect(plain).to include('No suggestions')
      expect(plain).to include('Alt+D')
    end

    it 'dismisses spell suggestions on the first escape and cancels on the second' do
      cancel_key = Shoko::Shared::KeyDefinitions::ACTIONS[:cancel].first
      component_with_note.show_spell_suggestions(component_with_note.spellcheck_target, ['ambiguous'])

      expect(component_with_note.handle_key(cancel_key)).to be_nil
      expect(component_with_note.handle_key(cancel_key)).to eq(type: :cancel)
    end
  end

  describe 'overlay sizing' do
    it 'respects minimum overlay dimensions' do
      small_bounds = Shoko::Adapters::Ui::Components::Rect.new(x: 1, y: 1, width: 60, height: 20)
      layout = component.send(:overlay_layout, small_bounds)

      expect(layout.width).to be >= 46
      expect(layout.height).to be >= 12
    end
  end
end
