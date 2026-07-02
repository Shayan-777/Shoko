# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::Controllers::StateController do
  subject(:controller) do
    deps = described_class::Dependencies.build(
      reader_state: reader_state,
      config_reader: config_reader,
      ui_state: ui_state,
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
      anchor_resolver: anchor_resolver,
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
  let(:reader_session_mutator) { instance_double('ReaderSessionMutator', quit_to_menu: nil) }
  let(:rendered_content_reader) { instance_double('RenderedContentReader') }
  let(:doc) { instance_double('Document', canonical_path: '/books/book.epub') }
  let(:document_reader) { -> { doc } }
  let(:terminal_service) { instance_double('TerminalService') }
  let(:progress_repository) do
    Class.new do
      include Shoko::Application::Ports::Outbound::ProgressRepository

      def save_for_book(book_path, chapter_index:, line_offset:, anchor: nil); end

      def find_by_book_path(book_path); end

      def find_all; end

      def exists_for_book?(book_path); end

      def last_updated_at(book_path); end

      def recent_books(limit: nil); end

      def save_if_further(book_path, chapter_index:, line_offset:, anchor: nil); end
    end.new
  end
  let(:bookmark_repository) { instance_double('BookmarkRepository') }
  let(:annotation_service) { instance_double('AnnotationService') }
  let(:logger) { instance_double('Logger', warn: nil, debug: nil) }
  let(:navigation_service) { instance_double('NavigationService') }
  let(:page_calculator) { nil }
  let(:layout_service) { instance_double('LayoutService') }
  let(:bookmark_service) { instance_double('BookmarkService') }
  let(:notification_service) { instance_double('NotificationService') }
  let(:position_anchor) do
    Shoko::Core::Models::DocumentAnchor.from_h(quote: 'It was the best of times', position: 0.25)
  end
  let(:anchor_resolver) { instance_double('AnchorResolver', capture_line: position_anchor) }
  let(:process_control) { instance_double('ProcessControl') }

  describe '#quit_to_menu' do
    it 'raises when saving progress fails' do
      allow(progress_repository).to receive(:save_for_book).and_raise(StandardError, 'disk full')

      expect { controller.quit_to_menu }.to raise_error(StandardError, 'disk full')
      expect(reader_session_mutator).not_to have_received(:quit_to_menu)
    end

    it 'saves progress with the captured position anchor and then quits on success' do
      allow(progress_repository).to receive(:save_for_book).and_return(nil)

      controller.quit_to_menu

      expect(anchor_resolver).to have_received(:capture_line).with(chapter_index: 1, line_offset: 42)
      expect(progress_repository).to have_received(:save_for_book).with(
        '/books/book.epub',
        chapter_index: 1,
        line_offset: 42,
        anchor: position_anchor.to_h
      )
      expect(reader_session_mutator).to have_received(:quit_to_menu)
    end

    it 'still saves the raw offsets when anchor capture fails' do
      allow(anchor_resolver).to receive(:capture_line).and_raise(StandardError, 'formatter edge case')
      allow(progress_repository).to receive(:save_for_book).and_return(nil)

      controller.quit_to_menu

      expect(progress_repository).to have_received(:save_for_book).with(
        '/books/book.epub',
        chapter_index: 1,
        line_offset: 42,
        anchor: nil
      )
      expect(reader_session_mutator).to have_received(:quit_to_menu)
    end
  end

  describe '#save_progress containment' do
    # Plain double: Shoko's logger takes structured kwargs, which a verifying
    # 'Logger' double (stdlib arity) would reject at the call site.
    let(:logger) { double('logger', error: nil) }
    let(:persistence_error) do
      Shoko::Adapters::Storage::Repositories::BaseRepository::PersistenceError.new('disk full')
    end

    it 'contains a domain persistence failure instead of unwinding the session' do
      allow(progress_repository).to receive(:save_for_book).and_raise(persistence_error)

      expect { controller.save_progress }.not_to raise_error
      expect(logger).to have_received(:error)
    end

    it 'still lets quit_to_menu proceed when the final save fails' do
      allow(progress_repository).to receive(:save_for_book).and_raise(persistence_error)

      controller.quit_to_menu

      expect(reader_session_mutator).to have_received(:quit_to_menu)
    end

    it 'propagates unexpected (non-domain) errors so bugs are not hidden' do
      allow(progress_repository).to receive(:save_for_book).and_raise(StandardError, 'unexpected')

      expect { controller.save_progress }.to raise_error(StandardError, 'unexpected')
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

    context 'with an anchored record' do
      let(:progress) do
        Shoko::Core::Models::ReadingProgress.new(
          chapter_index: 3, line_offset: 12, timestamp: nil, anchor: position_anchor.to_h
        )
      end

      it 'restores to the anchor re-located in the current layout, not the stored offset' do
        allow(anchor_resolver).to receive(:line_offset_for)
          .with(position_anchor.to_h, chapter_index: 3).and_return(31)

        controller.load_progress

        expect(reader_session_mutator).to have_received(:update_reader).with(single_page: 31, left_page: 31)
      end

      it 'falls back to the stored offset when the anchor cannot be located' do
        allow(anchor_resolver).to receive(:line_offset_for).and_return(nil)

        controller.load_progress

        expect(reader_session_mutator).to have_received(:update_reader).with(single_page: 12, left_page: 12)
      end

      it 'falls back to the stored offset when resolution raises' do
        allow(anchor_resolver).to receive(:line_offset_for).and_raise(StandardError, 'stream failure')

        controller.load_progress

        expect(reader_session_mutator).to have_received(:update_reader).with(single_page: 12, left_page: 12)
      end
    end
  end
end
