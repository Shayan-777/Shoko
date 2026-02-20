# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::Controllers::StateController do
  subject(:controller) do
    described_class.new(
      reader_state: reader_state,
      config_reader: config_reader,
      ui_state: ui_state,
      sidebar_state: sidebar_state,
      state_writer: state_writer,
      rendered_content_reader: rendered_content_reader,
      doc: doc,
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
    )
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
  let(:state_writer) { instance_double('StateWriter', quit_to_menu: nil) }
  let(:rendered_content_reader) { instance_double('RenderedContentReader') }
  let(:doc) { instance_double('Document', canonical_path: '/books/book.epub') }
  let(:terminal_service) { instance_double('TerminalService') }
  let(:progress_repository) { instance_double('ProgressRepository') }
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
    it 'still quits when saving progress raises' do
      allow(progress_repository).to receive(:save_for_book).and_raise(StandardError, 'disk full')

      expect { controller.quit_to_menu }.not_to raise_error
      expect(state_writer).to have_received(:quit_to_menu)
    end

    it 'saves progress and then quits on success' do
      allow(progress_repository).to receive(:save_for_book).and_return(nil)

      controller.quit_to_menu

      expect(progress_repository).to have_received(:save_for_book).with(
        '/books/book.epub',
        chapter_index: 1,
        line_offset: 42
      )
      expect(state_writer).to have_received(:quit_to_menu)
    end
  end
end
