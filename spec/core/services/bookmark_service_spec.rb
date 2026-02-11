# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Core::Services::BookmarkService do
  let(:bookmark_repository) do
    instance_double('BookmarkRepository',
                    add_for_book: bookmark,
                    delete_for_book: nil,
                    find_by_book_path: [bookmark],
                    exists_at_position?: false,
                    find_at_position: nil)
  end
  let(:domain_event_bus) { instance_double('DomainEventBus', publish: nil) }
  let(:config_reader) { instance_double('ConfigReader', view_mode: :single, page_numbering_mode: :absolute, line_spacing: :normal) }
  let(:reader_state_reader) do
    instance_double('ReaderNavigationReader',
                    current_chapter: 1,
                    single_page: 12,
                    left_page: 12,
                    current_page_index: 0,
                    book_path: '/books/a.epub')
  end
  let(:ui_state_reader) { instance_double('UIStateReader', terminal_width: 80, terminal_height: 24) }
  let(:state_writer) { instance_double('ReaderStateWriter', update_navigation: nil, update_bookmarks: nil) }
  let(:bookmark) { Struct.new(:chapter_index, :line_offset).new(1, 12) }

  subject(:service) do
    described_class.new(
      bookmark_repository: bookmark_repository,
      domain_event_bus: domain_event_bus,
      config_reader: config_reader,
      reader_state_reader: reader_state_reader,
      ui_state_reader: ui_state_reader,
      state_writer: state_writer
    )
  end

  it 'publishes BookmarkAdded through the domain event bus when adding a bookmark' do
    service.add_bookmark('note')

    expect(domain_event_bus).to have_received(:publish).with(instance_of(Shoko::Core::Events::BookmarkAdded))
  end

  it 'publishes BookmarkRemoved through the domain event bus when removing a bookmark' do
    service.remove_bookmark(bookmark)

    expect(domain_event_bus).to have_received(:publish).with(instance_of(Shoko::Core::Events::BookmarkRemoved))
  end

  it 'publishes BookmarkNavigated through the domain event bus when jumping to a bookmark' do
    service.jump_to_bookmark(bookmark)

    expect(domain_event_bus).to have_received(:publish).with(instance_of(Shoko::Core::Events::BookmarkNavigated))
  end
end
