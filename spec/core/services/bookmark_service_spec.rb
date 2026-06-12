# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Services::Reader::BookmarkService do
  class TestConfigStore
    def initialize(snapshot)
      @snapshot = snapshot
    end

    def load
      @snapshot
    end
  end

  class TestReaderSessionStore
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

  let(:bookmark_repository) do
    instance_double('BookmarkRepository',
                    add_for_book: bookmark,
                    delete_for_book: nil,
                    find_by_book_path: [bookmark],
                    exists_at_position?: false,
                    find_at_position: nil)
  end
  let(:domain_event_bus) { instance_double('DomainEventBus', publish: nil) }
  let(:domain_event_factory) { instance_double('DomainEventFactory') }
  let(:app_config_store) do
    TestConfigStore.new(
      Shoko::Application::Ports::Outbound::State::ConfigSnapshot.build(
        view_mode: :single,
        page_numbering_mode: :absolute,
        line_spacing: :normal
      )
    )
  end
  let(:reader_session_store) do
    TestReaderSessionStore.new(
      Shoko::Application::Ports::Outbound::State::ReaderSnapshot.build(
        current_chapter: 1,
        single_page: 12,
        left_page: 12,
        current_page_index: 0,
        book_path: '/books/a.epub',
        sidebar_visible: false
      )
    )
  end
  let(:reader_runtime_context) do
    instance_double(
      'ReaderRuntimeContext',
      terminal_size: Shoko::Application::Ports::Outbound::State::TerminalSize.build(width: 80, height: 24)
    )
  end
  let(:bookmark) { Struct.new(:chapter_index, :line_offset).new(1, 12) }

  subject(:service) do
    described_class.new(
      bookmark_repository: bookmark_repository,
      domain_event_bus: domain_event_bus,
      domain_event_factory: domain_event_factory,
      app_config_store: app_config_store,
      reader_session_store: reader_session_store,
      reader_runtime_context: reader_runtime_context
    )
  end

  before do
    allow(domain_event_factory).to receive(:build) do |event_class, **attrs|
      event_class.new(
        event_id: 'evt-1',
        occurred_at: Time.utc(2024, 1, 1, 0, 0, 0),
        **attrs
      )
    end
  end

  it 'publishes BookmarkAdded through the domain event bus when adding a bookmark' do
    service.add_bookmark('note')

    expect(domain_event_bus).to have_received(:publish).with(instance_of(Shoko::Core::Events::BookmarkAdded))
    expect(reader_session_store.load.bookmarks).to eq([bookmark])
  end

  it 'publishes BookmarkRemoved through the domain event bus when removing a bookmark' do
    service.remove_bookmark(bookmark)

    expect(domain_event_bus).to have_received(:publish).with(instance_of(Shoko::Core::Events::BookmarkRemoved))
    expect(reader_session_store.load.bookmarks).to eq([bookmark])
  end

  it 'publishes BookmarkNavigated through the domain event bus when jumping to a bookmark' do
    service.jump_to_bookmark(bookmark)

    expect(domain_event_bus).to have_received(:publish).with(instance_of(Shoko::Core::Events::BookmarkNavigated))
    expect(reader_session_store.load.current_chapter).to eq(1)
    expect(reader_session_store.load.current_page).to eq(12)
  end
end
