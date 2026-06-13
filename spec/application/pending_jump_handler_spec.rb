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

    def open_editor(text:, chapter_index:, annotation:)
      [text, chapter_index, annotation]
    end
  end

  let(:pending_jump) do
    Shoko::Core::Models::PendingJumpPayload.from_h(
      chapter_index: 3,
      edit: true,
      annotation: Shoko::Core::Models::AnnotationSelection.from_h(
        book_path: '/books/a.epub',
        annotation: {
          id: 'ann-1',
          text: 'Selected text',
          chapter_index: 3,
          anchor: { quote: 'Selected text' }
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
  let(:navigation_service) do
    instance_double('NavigationService', jump_to_chapter: nil, jump_to_chapter_offset: nil)
  end
  let(:anchor_resolver) { instance_double('AnchorResolver') }

  it 'resolves the annotation anchor to a precise offset, opens the editor, and clears the payload' do
    allow(anchor_resolver).to receive(:line_offset_for).and_return(7)

    handler = described_class.new(
      reader_session_store: reader_session_store,
      annotation_editor_launcher: annotation_editor_launcher,
      navigation_service: navigation_service,
      anchor_resolver: anchor_resolver
    )

    expect(anchor_resolver).to receive(:line_offset_for).with(
      an_instance_of(Shoko::Core::Models::DocumentAnchor), chapter_index: 3
    ).and_return(7)
    expect(navigation_service).to receive(:jump_to_chapter_offset).with(3, 7)
    expect(navigation_service).not_to receive(:jump_to_chapter)
    expect(annotation_editor_launcher).to receive(:open_editor).with(
      text: 'Selected text',
      chapter_index: 3,
      annotation: hash_including(id: 'ann-1')
    )

    handler.apply

    expect(reader_session_store.load.pending_jump).to be_nil
  end

  it 'falls back to the chapter start when the anchor cannot be located' do
    allow(anchor_resolver).to receive(:line_offset_for).and_return(nil)

    handler = described_class.new(
      reader_session_store: reader_session_store,
      annotation_editor_launcher: annotation_editor_launcher,
      navigation_service: navigation_service,
      anchor_resolver: anchor_resolver
    )

    expect(navigation_service).to receive(:jump_to_chapter).with(3)
    expect(navigation_service).not_to receive(:jump_to_chapter_offset)

    handler.apply
  end
end
