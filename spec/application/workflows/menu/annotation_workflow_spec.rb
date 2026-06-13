# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Workflows::Menu::AnnotationWorkflow do
  class AnnotationWorkflowTestMenuSessionStore
    include Shoko::Application::Ports::Outbound::MenuSessionStore

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

  class AnnotationWorkflowTestReaderSessionStore
    include Shoko::Application::Ports::Outbound::ReaderSessionStore

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

  class AnnotationWorkflowTestMenuTransientStore
    include Shoko::Application::Ports::Outbound::MenuTransientStore

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

  class AnnotationWorkflowTestModeSwitcher
    include Shoko::Application::Ports::Outbound::MenuModeSwitcher

    attr_reader :modes

    def initialize
      @modes = []
    end

    def switch_mode(mode)
      @modes << mode
    end
  end

  class AnnotationWorkflowTestSelectedAnnotationReader
    include Shoko::Application::Ports::Outbound::AnnotationSelectionReader

    attr_accessor :selection

    def selected_annotation
      @selection
    end
  end

  class AnnotationWorkflowTestAnnotationsViewRefresher
    include Shoko::Application::Ports::Outbound::AnnotationViewRefresher

    attr_reader :refresh_count

    def initialize
      @refresh_count = 0
    end

    def refresh_annotations_view
      @refresh_count += 1
    end
  end

  class AnnotationWorkflowTestReaderRunner
    include Shoko::Application::Ports::Outbound::ReaderRunner

    attr_reader :paths

    def initialize
      @paths = []
    end

    def run_reader(path)
      @paths << path
    end
  end

  let(:selection) do
    Shoko::Core::Models::AnnotationSelection.from_h(
      book_path: '/books/a.epub',
      annotation: {
        id: 'ann-1',
        text: 'Selected text',
        note: 'Saved note',
        chapter_index: 3,
        anchor: { quote: 'Selected text' },
      }
    )
  end
  let(:menu_session_store) do
    AnnotationWorkflowTestMenuSessionStore.new(Shoko::Application::Ports::Outbound::State::MenuSessionSnapshot.build)
  end
  let(:menu_transient_store) do
    AnnotationWorkflowTestMenuTransientStore.new(Shoko::Application::Ports::Outbound::State::MenuTransientSnapshot.build)
  end
  let(:reader_session_store) { AnnotationWorkflowTestReaderSessionStore.new(Shoko::Application::Ports::Outbound::State::ReaderSnapshot.build) }
  let(:mode_switcher) { AnnotationWorkflowTestModeSwitcher.new }
  let(:selected_annotation_reader) do
    AnnotationWorkflowTestSelectedAnnotationReader.new.tap { |reader| reader.selection = selection }
  end
  let(:annotations_view_refresher) { AnnotationWorkflowTestAnnotationsViewRefresher.new }
  let(:reader_runner) { AnnotationWorkflowTestReaderRunner.new }
  let(:annotation_service) do
    instance_double(
      'AnnotationService',
      delete: true,
      update: true,
      list_all: { '/books/a.epub' => [selection.to_annotation_h] }
    )
  end

  subject(:workflow) do
    described_class.new(
      mode_switcher: mode_switcher,
      menu_session_store: menu_session_store,
      reader_session_store: reader_session_store,
      annotation_service: annotation_service,
      logger: nil,
      selected_annotation_reader: selected_annotation_reader,
      annotations_view_refresher: annotations_view_refresher,
      reader_runner: reader_runner,
      menu_transient_store: menu_transient_store
    )
  end

  it 'stores pending jump in the reader session before opening the selected annotation' do
    workflow.open_selected_annotation

    snapshot = reader_session_store.load
    expect(snapshot.book_path).to eq('/books/a.epub')
    expect(snapshot.pending_jump).to be_a(Shoko::Core::Models::PendingJumpPayload)
    expect(reader_runner.paths).to eq(['/books/a.epub'])
  end

  it 'populates menu annotation edit state and switches mode for editing' do
    workflow.open_selected_annotation_for_edit

    snapshot = menu_session_store.load
    expect(snapshot.selected_annotation).to eq(selection.to_annotation_h)
    expect(snapshot.selected_annotation_book).to eq('/books/a.epub')
    expect(snapshot.annotation_edit_text).to eq('Saved note')
    expect(mode_switcher.modes).to eq([:annotation_editor])
  end

  it 'stores refreshed annotations in the transient menu slice after deletion' do
    workflow.delete_selected_annotation

    expect(annotation_service).to have_received(:delete).with('/books/a.epub', 'ann-1')
    expect(menu_transient_store.load.annotations_all).to eq({ '/books/a.epub' => [selection.to_annotation_h] })
    expect(annotations_view_refresher.refresh_count).to eq(1)
  end
end
