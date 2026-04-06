# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Ui::Components::Screens::TranslatorScreenComponent do
  def strip_ansi(text)
    text.to_s.gsub(%r{\e\[[0-9;]*[ -/]*[@-~]}, '')
  end

  def rasterize_screen(writes, width:, height:)
    grid = Array.new(height) { Array.new(width, ' ') }
    writes.each do |write|
      row = write[:row].to_i - 1
      col = write[:col].to_i - 1
      next unless row.between?(0, height - 1)

      strip_ansi(write[:text]).each_char.with_index do |char, offset|
        current_col = col + offset
        next unless current_col.between?(0, width - 1)

        grid[row][current_col] = char
      end
    end
    grid.map(&:join)
  end

  let(:terminal) { Shoko::TestSupport::TerminalDouble }
  let(:surface) { Shoko::Adapters::Ui::Components::Surface.new(terminal) }
  let(:bounds) { Shoko::Adapters::Ui::Components::Rect.new(x: 1, y: 1, width: 120, height: 30) }
  let(:menu_state_class) do
    Struct.new(
      :mode,
      :translator_focus,
      :translator_status,
      :translator_input_text,
      :translator_input_cursor,
      :translator_output_text,
      :translator_message,
      :translator_detected_source_lang,
      :translator_dropdown_selected,
      :translator_source_lang,
      :translator_target_lang,
      :translator_languages,
      :translator_selection,
      :translator_context_menu
    )
  end
  let(:dependencies_class) { Struct.new(:menu_state_reader) }
  let(:menu_state_reader) do
    menu_state_class.new(
      :translator,
      :input,
      :done,
      'Hallo Welt',
      5,
      'Hello world',
      'Translated de -> en',
      'de',
      0,
      'auto',
      'en',
      [
        { code: 'en', name: 'English' },
        { code: 'de', name: 'German' },
        { code: 'fr', name: 'French' },
        { code: 'es', name: 'Spanish' },
        { code: 'it', name: 'Italian' },
        { code: 'nl', name: 'Dutch' },
      ],
      nil,
      nil
    )
  end
  let(:dependencies) { dependencies_class.new(menu_state_reader) }

  subject(:component) { described_class.new(dependencies: dependencies) }

  before do
    terminal.reset!
  end

  it 'renders translator title, source text, and translated output' do
    component.render(surface, bounds)

    raw = terminal.writes.map { |write| write[:text] }.join("\n")
    rendered = strip_ansi(raw)
    palette = Shoko::Adapters::Ui::Constants::ComponentPalettes.fetch(:translator_screen, :dark)

    expect(rendered).to include('Translator')
    expect(rendered).to include('SOURCE')
    expect(rendered).to include('RESULT')
    expect(rendered).to include('Hallo')
    expect(rendered).to include('Hello world')
    expect(rendered).to include('Detected: German')
    expect(raw).to include(palette[:source_accent])
    expect(raw).to include(palette[:target_accent])
  end

  it 'maps header and body clicks to translator actions' do
    layout = component.send(:layout_metrics, bounds)
    source_box = layout[:left_box]
    body_row = component.send(:body_start_row, source_box, :source)

    header_hit = component.hit_test(source_box.col + 3, source_box.row + 1, bounds)
    body_hit = component.hit_test(source_box.col + 3, body_row, bounds)

    expect(header_hit).to eq(type: :toggle_dropdown, kind: :source)
    expect(body_hit).to eq(type: :focus, focus: :input)
  end

  it 'renders a 5-row dropdown window with a scrollbar when more languages exist' do
    menu_state_reader.mode = :translator_source_dropdown

    component.render(surface, bounds)

    layout = component.send(:layout_metrics, bounds)
    popup_box = component.send(:dropdown_popup_box, layout[:left_box], :source)
    screen = rasterize_screen(terminal.writes, width: bounds.width, height: bounds.height)

    item_rows = ((popup_box.row + 1)...(popup_box.row + popup_box.height - 1)).map do |row|
      screen[row - 1][(popup_box.col - 1)...(popup_box.col + popup_box.width - 1)]
    end
    rendered_dropdown = item_rows.join("\n")

    expect(item_rows.length).to eq(5)
    expect(rendered_dropdown).to include('AUTO Auto Detect')
    expect(rendered_dropdown).to include('EN   English')
    expect(rendered_dropdown).to include('DE   German')
    expect(rendered_dropdown).to include('FR   French')
    expect(rendered_dropdown).to include('ES   Spanish')
    expect(rendered_dropdown).not_to include('Italian')
    expect(rendered_dropdown).to include('█')
    expect(rendered_dropdown).to include('│')
  end

  it 'maps wrapped body coordinates into source and target selection ranges' do
    layout = component.send(:layout_metrics, bounds)
    source_box = layout[:left_box]
    target_box = layout[:right_box]
    body_row = component.send(:body_start_row, source_box, :source)

    source_selection = component.selection_from_points(
      start_column: source_box.col + 2,
      start_row: body_row,
      end_column: source_box.col + 7,
      end_row: body_row,
      bounds: bounds
    )
    target_selection = component.selection_from_points(
      start_column: target_box.col + 2,
      start_row: body_row,
      end_column: target_box.col + 7,
      end_row: body_row,
      bounds: bounds
    )

    expect(source_selection).to eq(pane: :source, start_index: 0, end_index: 5)
    expect(target_selection).to eq(pane: :target, start_index: 0, end_index: 5)
    expect(component.selection_text(target_selection)).to eq('Hello')
  end

  it 'disables copy in the context menu until a matching pane selection exists' do
    menu_state_reader.translator_context_menu = {
      pane: :source,
      anchor_column: 40,
      anchor_row: 12,
      paste_index: 2,
      replace_selection: false,
    }

    popup_box = component.context_menu_popup_box(bounds)

    expect(component.context_menu_hit(popup_box.col + 2, popup_box.row + 1, bounds)).to be_nil
    expect(component.context_menu_hit(popup_box.col + 2, popup_box.row + 2, bounds)).to include(id: :paste_from_clipboard)

    menu_state_reader.translator_selection = { pane: :source, start_index: 0, end_index: 5 }

    expect(component.context_menu_hit(popup_box.col + 2, popup_box.row + 1, bounds)).to include(id: :copy_to_clipboard)
  end

  it 'renders selection highlight and translator clipboard actions' do
    menu_state_reader.translator_selection = { pane: :target, start_index: 0, end_index: 5 }
    menu_state_reader.translator_context_menu = {
      pane: :target,
      anchor_column: 76,
      anchor_row: 11,
      paste_index: 5,
      replace_selection: false,
    }

    component.render(surface, bounds)

    raw = terminal.writes.map { |write| write[:text] }.join("\n")
    rendered = strip_ansi(raw)

    expect(raw).to include(Shoko::Adapters::Ui::Constants::Ui::MENU_SELECTION_BG)
    expect(rendered).to include('Copy to Clipboard')
    expect(rendered).to include('Paste from Clipboard')
  end
end
