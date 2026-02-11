# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Output::Ui::Sessions::AnnotationOverlayUiSessionAdapter do
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
                    handle_character: nil,
                    handle_backspace: nil,
                    handle_enter: nil,
                    handle_move_left: nil,
                    handle_move_right: nil,
                    handle_move_up: nil,
                    handle_move_down: nil,
                    handle_save: { type: :save, note: 'n' },
                    handle_click: { type: :cancel },
                    annotation_id: 42,
                    selected_text: 'sel',
                    note: 'note',
                    selection_range: { start: 1, end: 2 },
                    chapter_index: 3)
  end
  let(:reader_state_reader) do
    instance_double('ReaderStateReader',
                    annotations_overlay: annotations_overlay,
                    annotation_editor_overlay: editor_overlay)
  end
  let(:state_writer) { instance_double('ReaderStateWriter', update_reader: nil) }
  let(:ui_component_factory) do
    instance_double('UIFactory',
                    annotations_overlay: annotations_overlay,
                    annotation_editor_overlay: editor_overlay)
  end
  let(:logger) { instance_double('Logger', error: nil) }

  subject(:session) do
    described_class.new(
      reader_state_reader: reader_state_reader,
      state_writer: state_writer,
      ui_component_factory: ui_component_factory,
      logger: logger
    )
  end

  it 'opens and closes annotations overlay with outcomes' do
    open_outcome = session.open_annotations
    close_outcome = session.close_annotations

    expect(open_outcome.ok).to be(true)
    expect(close_outcome.ok).to be(true)
    expect(state_writer).to have_received(:update_reader).with(annotations_overlay: annotations_overlay)
    expect(annotations_overlay).to have_received(:hide)
    expect(state_writer).to have_received(:update_reader).with(annotations_overlay: nil)
  end

  it 'wraps overlay events in outcome payloads' do
    outcome = session.annotations_open

    expect(outcome.ok).to be(true)
    expect(outcome.payload).to eq(type: :open, annotation: { id: 7, text: 'n' })
  end

  it 'opens editor, handles editor events, and exposes editor context' do
    open_outcome = session.open_editor(text: 't', range: { a: 1 }, chapter_index: 1, annotation: nil)
    save_outcome = session.editor_save
    click_outcome = session.handle_editor_click(10, 2)

    expect(open_outcome.ok).to be(true)
    expect(save_outcome.ok).to be(true)
    expect(save_outcome.payload).to eq(type: :save, note: 'n')
    expect(click_outcome.ok).to be(true)
    expect(click_outcome.payload).to eq(type: :cancel)
    expect(session.editor_context).to eq(
      annotation_id: 42,
      selected_text: 'sel',
      note: 'note',
      selection_range: { start: 1, end: 2 },
      chapter_index: 3
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
end
