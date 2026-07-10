# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::UseCases::Reader::Actions::Navigation do
  class NavigationActionTestReaderSessionStore
    include Shoko::Application::Ports::Outbound::ReaderSessionStore

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

  let(:navigation_service) { instance_double(Shoko::Application::Services::Reader::NavigationService, jump_to_chapter: nil) }
  let(:bookmark_service) { double('BookmarkService').as_null_object }

  def build(current_chapter:, total_chapters:)
    store = NavigationActionTestReaderSessionStore.new(
      Shoko::Application::Ports::Outbound::State::ReaderSnapshot.build(
        current_chapter: current_chapter, total_chapters: total_chapters
      )
    )
    described_class.new(navigation_service: navigation_service, bookmark_service: bookmark_service,
                        reader_session_store: store)
  end

  it 'advances to the next chapter from the middle of the book' do
    expect(build(current_chapter: 1, total_chapters: 3).call(:next_chapter)).to eq(:handled)
    expect(navigation_service).to have_received(:jump_to_chapter).with(2)
  end

  it 'does not advance past the last chapter (the "n"-on-the-last-chapter crash)' do
    expect(build(current_chapter: 2, total_chapters: 3).call(:next_chapter)).to eq(:handled)
    expect(navigation_service).not_to have_received(:jump_to_chapter)
  end

  it 'steps to the previous chapter from the middle of the book' do
    build(current_chapter: 1, total_chapters: 3).call(:prev_chapter)
    expect(navigation_service).to have_received(:jump_to_chapter).with(0)
  end

  it 'does not step before the first chapter' do
    expect(build(current_chapter: 0, total_chapters: 3).call(:prev_chapter)).to eq(:handled)
    expect(navigation_service).not_to have_received(:jump_to_chapter)
  end
end
