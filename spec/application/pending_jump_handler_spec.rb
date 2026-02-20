# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::PendingJumpHandler do
  let(:pending_jump) do
    {
      chapter_index: 3,
      selection_range: { start: { x: 1, y: 2 }, end: { x: 4, y: 2 } },
      edit: true,
      annotation: {
        id: 'ann-1',
        text: 'Selected text',
        chapter_index: 3,
        range: { start: 10, end: 20 },
      },
    }
  end
  let(:reader_state) { instance_double('ReaderStateReader', pending_jump: pending_jump) }
  let(:state_writer) { instance_double('StateWriter', update_reader: nil, update_selections: nil) }
  let(:annotation_editor_session) { instance_double('AnnotationEditorSession', open_editor: nil) }
  let(:rendered_content_reader) { instance_double('RenderedContentReader') }
  let(:navigation_service) { instance_double('NavigationService', jump_to_chapter: nil) }
  let(:selection_service) { instance_double('SelectionService', normalize_range: { normalized: true }) }

  it 'applies pending jump using injected services and clears pending payload' do
    handler = described_class.new(
      reader_state: reader_state,
      state_writer: state_writer,
      annotation_editor_session: annotation_editor_session,
      rendered_content_reader: rendered_content_reader,
      navigation_service: navigation_service,
      selection_service: selection_service
    )

    expect(navigation_service).to receive(:jump_to_chapter).with(3)
    expect(selection_service).to receive(:normalize_range).with(
      rendered_content_reader: rendered_content_reader,
      selection_range: pending_jump[:selection_range]
    ).and_return(normalized: true)
    expect(state_writer).to receive(:update_reader).with(selection: { normalized: true })
    expect(annotation_editor_session).to receive(:open_editor).with(
      text: 'Selected text',
      range: { start: 10, end: 20 },
      chapter_index: 3,
      annotation: hash_including(id: 'ann-1')
    )
    expect(state_writer).to receive(:update_selections).with(pending_jump: nil)

    handler.apply
  end
end
