# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::Controllers::SidebarController do
  let(:toc_entry_class) { Struct.new(:chapter_index, :href, :level, :title, keyword_init: true) }
  let(:reader_state) { instance_double('ReaderState', bookmarks: [], annotations: []) }
  let(:config_reader) { instance_double('ConfigReader', view_mode: :single) }
  let(:ui_state) { instance_double('UiState') }
  let(:sidebar_state) do
    instance_double(
      'SidebarState',
      sidebar_visible?: true,
      sidebar_active_tab: :toc,
      sidebar_toc_selected: 0,
      sidebar_toc_collapsed: nil,
      sidebar_toc_filter_active?: false,
      sidebar_toc_filter: nil,
      sidebar_bookmarks_selected: 0,
      sidebar_annotations_selected: 0,
      sidebar_prev_view_mode: nil
    )
  end
  let(:state_writer) do
    instance_double(
      'StateWriter',
      update_sidebar: nil,
      update_reader: nil,
      update_config: nil,
      update_selections: nil
    )
  end
  let(:state_controller) { instance_double('StateController', jump_to_chapter_offset: nil, save_progress: nil) }
  let(:navigation_service) { instance_double('NavigationService', jump_to_chapter: nil) }
  let(:notification_service) { instance_double('NotificationService', set_message: nil) }
  let(:toc_entry) { toc_entry_class.new(chapter_index: 2, href: 'chapter3.xhtml#sec-1', level: 0, title: 'Chapter 3') }
  let(:document_class) do
    Class.new do
      include Shoko::Core::Ports::Outbound::ReaderDocument

      attr_accessor :toc_entries

      def initialize(toc_entries:)
        @toc_entries = toc_entries
      end

      def canonical_path
        '/books/sidebar.epub'
      end

      def cached?
        false
      end

      def chapter_count
        0
      end

      def get_chapter(_index)
        nil
      end
    end
  end
  let(:document) { document_class.new(toc_entries: [toc_entry]) }

  subject(:controller) do
    deps = described_class::Dependencies.new(
      reader_state: reader_state,
      config_reader: config_reader,
      ui_state: ui_state,
      sidebar_state: sidebar_state,
      state_writer: state_writer,
      document: document,
      navigation_service: navigation_service,
      state_controller: state_controller,
      bookmark_service: nil,
      ui_controller: nil,
      notification_service: notification_service,
      formatting_service: nil,
      layout_service: nil
    ).validate!
    described_class.new(deps: deps)
  end

  it 'jumps via chapter offset when TOC anchor resolves' do
    allow(controller).to receive(:line_offset_for_toc_entry).and_return(11)

    expect(state_controller).to receive(:jump_to_chapter_offset).with(2, 11)
    expect(navigation_service).not_to receive(:jump_to_chapter)
    expect(state_writer).to receive(:update_sidebar).with(visible: false)
    expect(state_writer).to receive(:update_reader).with(mode: :read)

    controller.sidebar_select
  end

  it 'falls back to chapter jump when no TOC anchor offset is available' do
    allow(controller).to receive(:line_offset_for_toc_entry).and_return(nil)

    expect(state_controller).not_to receive(:jump_to_chapter_offset)
    expect(navigation_service).to receive(:jump_to_chapter).with(2)
    expect(state_writer).to receive(:update_sidebar).with(visible: false)
    expect(state_writer).to receive(:update_reader).with(mode: :read)

    controller.sidebar_select
  end

  it 'routes TOC keyboard navigation through filtered visible indices' do
    allow(sidebar_state).to receive(:sidebar_toc_filter_active?).and_return(true)
    allow(sidebar_state).to receive(:sidebar_toc_filter).and_return('chapter 3')
    allow(sidebar_state).to receive(:sidebar_toc_selected).and_return(0)

    entries = [
      toc_entry_class.new(chapter_index: 0, href: nil, level: 0, title: 'Chapter 1'),
      toc_entry_class.new(chapter_index: 1, href: nil, level: 0, title: 'Chapter 2'),
      toc_entry_class.new(chapter_index: 2, href: nil, level: 0, title: 'Chapter 3')
    ]
    allow(document).to receive(:toc_entries).and_return(entries)

    expect(state_writer).to receive(:update_sidebar).with(hash_including(toc_selected: 2))

    controller.sidebar_down
  end

  it 'does not toggle collapse while toc filter is active' do
    allow(sidebar_state).to receive(:sidebar_toc_filter_active?).and_return(true)
    allow(sidebar_state).to receive(:sidebar_toc_filter).and_return('chapter')

    entries = [
      toc_entry_class.new(chapter_index: 0, href: nil, level: 0, title: 'Chapter 1'),
      toc_entry_class.new(chapter_index: 0, href: nil, level: 1, title: 'Section A')
    ]
    allow(document).to receive(:toc_entries).and_return(entries)
    allow(sidebar_state).to receive(:sidebar_toc_selected).and_return(0)

    expect(state_writer).not_to receive(:update_sidebar).with(hash_including(:toc_collapsed))

    controller.sidebar_toggle_toc
  end

  it 'selects visible filtered toc entry instead of hidden raw index' do
    allow(sidebar_state).to receive(:sidebar_toc_filter_active?).and_return(true)
    allow(sidebar_state).to receive(:sidebar_toc_filter).and_return('chapter 3')
    allow(sidebar_state).to receive(:sidebar_toc_selected).and_return(0)

    entries = [
      toc_entry_class.new(chapter_index: 0, href: nil, level: 0, title: 'Chapter 1'),
      toc_entry_class.new(chapter_index: 1, href: nil, level: 0, title: 'Chapter 2'),
      toc_entry_class.new(chapter_index: 2, href: nil, level: 0, title: 'Chapter 3')
    ]
    allow(document).to receive(:toc_entries).and_return(entries)
    allow(controller).to receive(:line_offset_for_toc_entry).and_return(nil)

    expect(navigation_service).to receive(:jump_to_chapter).with(2)
    expect(state_writer).to receive(:update_sidebar).with(visible: false)
    expect(state_writer).to receive(:update_reader).with(mode: :read)

    controller.sidebar_select
  end
end
