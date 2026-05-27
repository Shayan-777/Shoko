# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::PendingJumpHandler do
  class PendingJumpHandlerTestReaderSessionStore
    attr_reader :snapshot

    def initialize(snapshot)
      @snapshot = snapshot
    end

    def load
      @snapshot
    end

    def save(snapshot)
      @snapshot = snapshot
    end
  end

  class PendingJumpHandlerTestAnnotationEditorLauncher
    include Shoko::Application::Ports::Outbound::AnnotationEditorLauncher

    def open_editor(text:, range:, chapter_index:, annotation:)
      [text, range, chapter_index, annotation]
    end
  end

  class PendingJumpHandlerTestRenderedContentReader
    include Shoko::Application::Ports::Outbound::RenderedContentReader

    def rendered_lines
      []
    end
  end

  let(:pending_jump) do
    Shoko::Core::Models::PendingJumpPayload.from_h(
      chapter_index: 3,
      selection_range: { start: { x: 1, y: 2 }, end: { x: 4, y: 2 } },
      edit: true,
      annotation: Shoko::Core::Models::AnnotationSelection.from_h(
        book_path: '/books/a.epub',
        annotation: {
          id: 'ann-1',
          text: 'Selected text',
          chapter_index: 3,
          range: { start: 10, end: 20 }
        }
      )
    )
  end
  let(:reader_session_store) do
    PendingJumpHandlerTestReaderSessionStore.new(
      Shoko::Application::Ports::Outbound::State::ReaderSnapshot.build(pending_jump: pending_jump)
    )
  end
  let(:annotation_editor_launcher) { PendingJumpHandlerTestAnnotationEditorLauncher.new }
  let(:rendered_content_reader) { PendingJumpHandlerTestRenderedContentReader.new }
  let(:navigation_service) { instance_double('NavigationService', jump_to_chapter: nil) }
  let(:selection_service) { instance_double('SelectionService', normalize_range: { normalized: true }) }

  it 'applies pending jump using injected services and clears pending payload' do
    handler = described_class.new(
      reader_session_store: reader_session_store,
      annotation_editor_launcher: annotation_editor_launcher,
      rendered_content_reader: rendered_content_reader,
      navigation_service: navigation_service,
      selection_service: selection_service
    )

    expect(navigation_service).to receive(:jump_to_chapter).with(3)
    expect(selection_service).to receive(:normalize_range).with(
      rendered_content_reader: rendered_content_reader,
      selection_range: pending_jump.selection_range
    ).and_return(normalized: true)
    expect(annotation_editor_launcher).to receive(:open_editor).with(
      text: 'Selected text',
      range: { start: 10, end: 20 },
      chapter_index: 3,
      annotation: hash_including(id: 'ann-1')
    )

    handler.apply

    snapshot = reader_session_store.load
    expect(snapshot.selection).to eq(normalized: true)
    expect(snapshot.pending_jump).to be_nil
  end
end
