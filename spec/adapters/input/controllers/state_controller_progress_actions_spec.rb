# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::Controllers::StateController do
  subject(:controller) do
    deps = described_class::Dependencies.new(
      reader_state: reader_state,
      config_reader: config_reader,
      ui_state: ui_state,
      sidebar_state: sidebar_state,
      reader_session_mutator: reader_session_mutator,
      rendered_content_reader: rendered_content_reader,
      doc: doc,
      document_reader: document_reader,
      path: '/books/book.epub',
      terminal_service: terminal_service,
      progress_repository: progress_repository,
      bookmark_repository: bookmark_repository,
      annotation_service: annotation_service,
      logger: logger,
      navigation_service: navigation_service,
      page_calculator: page_calculator,
      layout_service: layout_service,
      bookmark_service: bookmark_service,
      notification_service: notification_service,
      coordinate_service: coordinate_service,
      process_control: process_control
    ).validate!
    described_class.new(deps: deps)
  end

  let(:reader_state) do
    instance_double(
      'ReaderState',
      current_chapter: 1,
      left_page: 42,
      single_page: 42,
      current_page_index: 0
    )
  end
  let(:config_reader) do
    instance_double(
      'ConfigReader',
      page_numbering_mode: :absolute,
      view_mode: :single
    )
  end
  let(:ui_state) { instance_double('UiState') }
  let(:sidebar_state) { instance_double('SidebarState') }
  let(:reader_session_mutator) { instance_double('ReaderSessionMutator', quit_to_menu: nil) }
  let(:rendered_content_reader) { instance_double('RenderedContentReader') }
  let(:doc) { instance_double('Document', canonical_path: '/books/book.epub') }
  let(:document_reader) { -> { doc } }
  let(:terminal_service) { instance_double('TerminalService') }
  let(:progress_repository) do
    Class.new do
      include Shoko::Core::Ports::Outbound::ProgressRepository

      def save_for_book(book_path, chapter_index:, line_offset:)
      end

      def find_by_book_path(book_path)
      end

      def find_all
      end

      def exists_for_book?(book_path)
      end

      def last_updated_at(book_path)
      end

      def recent_books(limit: nil)
      end

      def save_if_further(book_path, chapter_index:, line_offset:)
      end
    end.new
  end
  let(:bookmark_repository) { instance_double('BookmarkRepository') }
  let(:annotation_service) { instance_double('AnnotationService') }
  let(:logger) { instance_double('Logger', warn: nil) }
  let(:navigation_service) { instance_double('NavigationService') }
  let(:page_calculator) { nil }
  let(:layout_service) { instance_double('LayoutService') }
  let(:bookmark_service) { instance_double('BookmarkService') }
  let(:notification_service) { instance_double('NotificationService') }
  let(:coordinate_service) { instance_double('CoordinateService') }
  let(:process_control) { instance_double('ProcessControl') }

  describe '#quit_to_menu' do
    it 'raises when saving progress fails' do
      allow(progress_repository).to receive(:save_for_book).and_raise(StandardError, 'disk full')

      expect { controller.quit_to_menu }.to raise_error(StandardError, 'disk full')
      expect(reader_session_mutator).not_to have_received(:quit_to_menu)
    end

    it 'saves progress and then quits on success' do
      allow(progress_repository).to receive(:save_for_book).and_return(nil)

      controller.quit_to_menu

      expect(progress_repository).to have_received(:save_for_book).with(
        '/books/book.epub',
        chapter_index: 1,
        line_offset: 42
      )
      expect(reader_session_mutator).to have_received(:quit_to_menu)
    end
  end

  describe '#load_progress' do
    let(:doc) { nil }
    let(:loaded_doc) { instance_double('Document', canonical_path: '/books/book.epub', chapter_count: 7) }
    let(:document_reader) { -> { loaded_doc } }
    let(:progress) { Shoko::Core::Models::ReadingProgress.new(chapter_index: 3, line_offset: 12, timestamp: nil) }

    before do
      allow(progress_repository).to receive(:find_by_book_path).with('/books/book.epub').and_return(progress)
      allow(reader_session_mutator).to receive(:update_reader)
    end

    it 'restores progress from the live document reader when the constructor doc snapshot is nil' do
      controller.load_progress

      expect(progress_repository).to have_received(:find_by_book_path).with('/books/book.epub')
      expect(reader_session_mutator).to have_received(:update_reader).with(current_chapter: 3)
      expect(reader_session_mutator).to have_received(:update_reader).with(single_page: 12, left_page: 12)
    end
  end
end
