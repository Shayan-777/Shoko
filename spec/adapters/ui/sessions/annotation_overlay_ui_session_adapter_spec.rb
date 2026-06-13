# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Ui::Sessions::AnnotationOverlayUiSessionAdapter do
  let(:annotations_overlay) do
    instance_double('AnnotationsOverlay',
                    visible?: true,
                    hide: nil,
                    current_annotation: { id: 7, text: 'n' },
                    scroll_up: { type: :selection_change, index: 1 },
                    scroll_down: { type: :selection_change, index: 2 },
                    :'selected_index=' => nil)
  end
  let(:editor_overlay) do
    instance_double('AnnotationEditorOverlay',
                    visible?: true,
                    hide: nil,
                    update_color_mode: nil,
                    handle_character: nil,
                    handle_backspace: nil,
                    handle_enter: nil,
                    handle_move_left: nil,
                    handle_move_right: nil,
                    handle_move_up: nil,
                    handle_move_down: nil,
                    handle_cancel: { type: :cancel },
                    handle_save: { type: :save, note: 'n' },
                    spellcheck_target: { word: 'ambigues', start: 0, end: 8 },
                    spell_suggestion_state: { word: 'ambigues', start: 0, end: 8, scope_key: 'auto' },
                    show_spell_suggestions: nil,
                    handle_click: { type: :cancel },
                    annotation_id: 42,
                    selected_text: 'sel',
                    note: 'note',
                    chapter_index: 3)
  end
  let(:reader_state_reader) do
    instance_double('ReaderStateReader',
                    annotations_overlay: annotations_overlay,
                    annotation_editor_overlay: editor_overlay)
  end
  let(:reader_session_mutator) { instance_double('ReaderSessionMutator', update_reader: nil) }
  let(:rendered_content_reader) { instance_double('RenderedContentReader', rendered_lines: rendered_lines) }
  let(:rendered_lines) { { 'line-key' => { geometry: double('Geometry') } } }
  let(:ui_component_factory) do
    instance_double('UIFactory',
                    annotations_overlay: annotations_overlay,
                    annotation_editor_overlay: editor_overlay)
  end
  let(:logger) { instance_double('Logger', error: nil) }

  subject(:session) do
    described_class.new(
      reader_state_reader: reader_state_reader,
      reader_session_mutator: reader_session_mutator,
      ui_component_factory: ui_component_factory,
      rendered_content_reader: rendered_content_reader,
      logger: logger
    )
  end

  it 'opens and closes annotations overlay with outcomes' do
    open_outcome = session.open_annotations
    close_outcome = session.close_annotations

    expect(open_outcome.ok).to be(true)
    expect(close_outcome.ok).to be(true)
    expect(reader_session_mutator).to have_received(:update_reader).with(annotations_overlay: annotations_overlay)
    expect(annotations_overlay).to have_received(:hide)
    expect(reader_session_mutator).to have_received(:update_reader).with(annotations_overlay: nil)
  end

  it 'wraps overlay events in outcome payloads' do
    outcome = session.annotations_open

    expect(outcome.ok).to be(true)
    expect(outcome.payload).to eq(type: :open, annotation: { id: 7, text: 'n' })
  end

  it 'opens editor, handles editor events, and exposes editor context' do
    expect(ui_component_factory).to receive(:annotation_editor_overlay).with(
      reader_state_reader: reader_state_reader,
      reader_session_mutator: reader_session_mutator,
      rendered_lines: rendered_lines
    ).and_return(editor_overlay)

    open_outcome = session.open_editor(text: 't', chapter_index: 1, annotation: nil)
    save_outcome = session.editor_save
    click_outcome = session.handle_editor_click(10, 2)

    expect(open_outcome.ok).to be(true)
    expect(reader_session_mutator).to have_received(:update_reader).with(
      annotation_editor_note: '',
      annotation_editor_cursor: 0,
      annotation_editor_selected_text: 't',
      annotation_editor_chapter_index: 1,
      annotation_editor_annotation_id: nil
    )
    expect(reader_session_mutator).to have_received(:update_reader).with(annotation_editor_overlay: editor_overlay)
    expect(save_outcome.ok).to be(true)
    expect(save_outcome.payload).to eq(type: :save, note: 'n')
    expect(click_outcome.ok).to be(true)
    expect(click_outcome.payload).to eq(type: :cancel)
    expect(session.editor_context).to eq(
      annotation_id: 42,
      selected_text: 'sel',
      note: 'note',
      chapter_index: 3
    )
  end

  it 'does not expose non-event editor return values as payloads' do
    allow(editor_overlay).to receive(:handle_character).with('a').and_return(1.2345)

    outcome = session.editor_insert_char('a')

    expect(outcome.ok).to be(true)
    expect(outcome.payload).to be_nil
  end

  it 'exposes spellcheck target and suggestion rendering hooks on the editor overlay' do
    target = { word: 'ambigues', start: 0, end: 8 }

    target_outcome = session.editor_spellcheck_target
    state_outcome = session.editor_spell_suggestions_state
    show_outcome = session.editor_show_spell_suggestions(
      target: target,
      suggestions: ['ambiguous'],
      scope_key: 'auto',
      scope_label: 'Auto',
      can_cycle: true
    )

    expect(target_outcome.ok).to be(true)
    expect(target_outcome.payload).to eq(target)
    expect(state_outcome.ok).to be(true)
    expect(state_outcome.payload).to eq(word: 'ambigues', start: 0, end: 8, scope_key: 'auto')
    expect(show_outcome.ok).to be(true)
    expect(editor_overlay).to have_received(:show_spell_suggestions).with(
      target,
      ['ambiguous'],
      scope_key: 'auto',
      scope_label: 'Auto',
      can_cycle: true
    )
  end

  it 'logs and returns failed outcomes when overlay interaction raises' do
    allow(annotations_overlay).to receive(:scroll_up).and_raise(RuntimeError, 'boom')

    outcome = session.annotations_up

    expect(outcome.ok).to be(false)
    expect(outcome.code).to eq(:annotations_up_failed)
    expect(logger).to have_received(:error).with(
      'annotation.session.annotations_up',
      hash_including(error: 'RuntimeError', message: 'boom')
    )
  end

  it 'refreshes active annotation editor theme mode' do
    session.refresh_theme(color_mode: :light)
    expect(editor_overlay).to have_received(:update_color_mode).with(:light)
  end
end
