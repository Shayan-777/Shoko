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

  def build_state(note: '', cursor: 0, selected_text: 'Quoted text', chapter_index: 0, annotation_id: nil)
    Struct.new(:annotation_editor_note, :annotation_editor_cursor, :annotation_editor_selected_text,
               :annotation_editor_chapter_index,
               :annotation_editor_annotation_id).new(
                 note, cursor, selected_text, chapter_index, annotation_id
               )
  end

  let(:state) { build_state }
  let(:mutator) do
    Class.new do
      def initialize(state)
        @state = state
      end

      def update_reader(attributes)
        attributes.each do |key, value|
          @state[key] = value if @state.members.include?(key)
        end
      end
    end.new(state)
  end

  subject(:component) do
    described_class.new(reader_state_reader: state, reader_session_mutator: mutator)
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

    it 'wraps and pads wide (CJK) quotes by display width so they stay inside the panel' do
      wide_state = build_state(selected_text: ('漢字テキスト ' * 10).strip)
      wide_component = described_class.new(reader_state_reader: wide_state, reader_session_mutator: mutator)

      wide_component.render(surface, bounds)

      metrics = Shoko::Shared::Terminal::TextMetrics
      quote_rows = terminal.writes.map { |write| strip_ansi(write[:text]) }.select { |text| text.include?('│') }
      layout = wide_component.send(:overlay_layout, bounds)
      max_width = layout.width - (2 * described_class::PADDING_H)

      expect(quote_rows).not_to be_empty
      expect(quote_rows.map { |text| metrics.visible_length(text) }).to all(be <= max_width)
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
      palette = Shoko::Adapters::Ui::Constants::ComponentPalettes.fetch(:annotation_editor_overlay, :light)

      expect(rendered).to include(palette[:panel_bg])
      expect(rendered).to include(palette[:panel_fg])
      expect(rendered).to include(palette[:quote_bg])
      expect(rendered).to include(palette[:backdrop_fg])
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
    let(:state_with_note) { build_state(note: 'This is ambigues', cursor: 'This is ambigues'.length) }
    let(:mutator_with_note) do
      Class.new do
        def initialize(state)
          @state = state
        end

        def update_reader(attributes)
          attributes.each do |key, value|
            @state[key] = value if @state.members.include?(key)
          end
        end
      end.new(state_with_note)
    end

    subject(:component_with_note) do
      described_class.new(reader_state_reader: state_with_note, reader_session_mutator: mutator_with_note)
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

    it 'bounds the popup to the note viewport and keeps the selected suggestion visible' do
      target = component_with_note.spellcheck_target
      suggestions = %w[amber angle amply amuse anchor]
      component_with_note.show_spell_suggestions(
        target,
        suggestions,
        scope_key: 'lang:en',
        scope_label: 'English',
        can_cycle: true
      )
      3.times { component_with_note.handle_move_down }

      state = component_with_note.send(:note_render_state, component_with_note.note, 24, 2)
      state[:start_row] = 8
      popup = component_with_note.instance_variable_get(:@spell_suggestions)

      payload = component_with_note.send(:spell_popup_render_payload, { x: 4 }, state, popup)
      popup_plain = payload[:lines].map { |line| strip_ansi(line) }.join("\n")

      expect(payload[:lines].length).to eq(2)
      expect(payload[:row]).to be_between(8, 8).inclusive
      expect(popup_plain).to include('amuse')
    end

    it 'renders without crashing when spell suggestions reopen on a short overlay' do
      constrained_bounds = Shoko::Adapters::Ui::Components::Rect.new(x: 1, y: 1, width: 60, height: 20)
      target = component_with_note.spellcheck_target
      first_scope = %w[amber angle amply amuse anchor]
      second_scope = %w[amend amid amass amaze]

      component_with_note.show_spell_suggestions(
        target,
        first_scope,
        scope_key: 'lang:en',
        scope_label: 'English',
        can_cycle: true
      )
      component_with_note.show_spell_suggestions(
        target,
        second_scope,
        scope_key: 'lang:de',
        scope_label: 'German',
        can_cycle: true
      )

      expect { component_with_note.render(surface, constrained_bounds) }.not_to raise_error

      rendered = terminal.writes.map { |write| write[:text] }.join("\n")
      plain = strip_ansi(rendered)
      expect(plain).to include('German')
      expect(plain).to include('amaze')
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
