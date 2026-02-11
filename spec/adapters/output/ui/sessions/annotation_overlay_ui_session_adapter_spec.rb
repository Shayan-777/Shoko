# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Output::Ui::Sessions::AnnotationOverlayUiSessionAdapter do
  let(:annotations_overlay) do
    instance_double('AnnotationsOverlay',
                    visible?: true,
                    hide: nil,
                    current_annotation: { id: 7, text: 'n' },
                    :'selected_index=' => nil)
  end
  let(:editor_overlay) do
    instance_double('AnnotationEditorOverlay',
                    visible?: true,
                    hide: nil,
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

  subject(:session) do
    described_class.new(
      reader_state_reader: reader_state_reader,
      state_writer: state_writer,
      ui_component_factory: ui_component_factory
    )
  end

  it 'opens and closes annotations overlay' do
    expect(session.open_annotations).to be(true)
    expect(state_writer).to have_received(:update_reader).with(annotations_overlay: annotations_overlay)

    expect(session.close_annotations).to be(true)
    expect(annotations_overlay).to have_received(:hide)
    expect(state_writer).to have_received(:update_reader).with(annotations_overlay: nil)
  end

  it 'handles overlay input and selection updates' do
    expect(session.annotations_open).to eq(type: :open, annotation: { id: 7, text: 'n' })
    expect(session.set_annotations_selected_index(2)).to be(true)
    expect(annotations_overlay).to have_received(:selected_index=).with(2)
  end

  it 'opens editor, handles editor events, and exposes editor context' do
    expect(session.open_editor(text: 't', range: { a: 1 }, chapter_index: 1, annotation: nil)).to be(true)
    expect(state_writer).to have_received(:update_reader).with(annotation_editor_overlay: editor_overlay)
    expect(session.editor_save).to eq(type: :save, note: 'n')
    expect(session.handle_editor_click(10, 2)).to eq(type: :cancel)
    expect(session.editor_context).to eq(
      annotation_id: 42,
      selected_text: 'sel',
      note: 'note',
      selection_range: { start: 1, end: 2 },
      chapter_index: 3
    )
  end
end
