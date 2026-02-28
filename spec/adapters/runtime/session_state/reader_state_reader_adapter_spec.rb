# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Runtime::SessionState::ReaderStateReaderAdapter do
  let(:state) { double('state') }
  let(:adapter) { described_class.new(state) }

  before do
    allow(state).to receive(:get).and_return(nil)
  end

  describe '#current_chapter' do
    it 'delegates to ReaderSelectors' do
      allow(Shoko::Adapters::Runtime::SessionState::Selectors::ReaderSelectors).to receive(:current_chapter).with(state).and_return(5)
      expect(adapter.current_chapter).to eq(5)
    end

    it 'returns 0 when nil' do
      allow(Shoko::Adapters::Runtime::SessionState::Selectors::ReaderSelectors).to receive(:current_chapter).with(state).and_return(nil)
      expect(adapter.current_chapter).to eq(0)
    end
  end

  describe '#total_chapters' do
    it 'reads from state' do
      allow(state).to receive(:get).with(%i[reader total_chapters]).and_return(10)
      expect(adapter.total_chapters).to eq(10)
    end

    it 'returns 0 when nil' do
      allow(state).to receive(:get).with(%i[reader total_chapters]).and_return(nil)
      expect(adapter.total_chapters).to eq(0)
    end
  end

  describe '#current_page_index' do
    it 'delegates to ReaderSelectors' do
      allow(Shoko::Adapters::Runtime::SessionState::Selectors::ReaderSelectors).to receive(:current_page_index).with(state).and_return(3)
      expect(adapter.current_page_index).to eq(3)
    end
  end

  describe '#left_page' do
    it 'delegates to ReaderSelectors' do
      allow(Shoko::Adapters::Runtime::SessionState::Selectors::ReaderSelectors).to receive(:left_page).with(state).and_return(100)
      expect(adapter.left_page).to eq(100)
    end
  end

  describe '#right_page' do
    it 'delegates to ReaderSelectors' do
      allow(Shoko::Adapters::Runtime::SessionState::Selectors::ReaderSelectors).to receive(:right_page).with(state).and_return(120)
      expect(adapter.right_page).to eq(120)
    end
  end

  describe '#single_page' do
    it 'delegates to ReaderSelectors' do
      allow(Shoko::Adapters::Runtime::SessionState::Selectors::ReaderSelectors).to receive(:single_page).with(state).and_return(50)
      expect(adapter.single_page).to eq(50)
    end
  end

  describe '#current_page' do
    it 'reads from state' do
      allow(state).to receive(:get).with(%i[reader current_page]).and_return(25)
      expect(adapter.current_page).to eq(25)
    end
  end

  describe '#page_map' do
    it 'delegates to ReaderSelectors' do
      allow(Shoko::Adapters::Runtime::SessionState::Selectors::ReaderSelectors).to receive(:page_map).with(state).and_return([10, 20, 30])
      expect(adapter.page_map).to eq([10, 20, 30])
    end
  end

  describe '#book_path' do
    it 'reads from state' do
      allow(state).to receive(:get).with(%i[reader book_path]).and_return('/path/to/book.epub')
      expect(adapter.book_path).to eq('/path/to/book.epub')
    end
  end

  describe '#bookmarks' do
    it 'delegates to ReaderSelectors' do
      bookmarks = [double('bookmark1'), double('bookmark2')]
      allow(Shoko::Adapters::Runtime::SessionState::Selectors::ReaderSelectors).to receive(:bookmarks).with(state).and_return(bookmarks)
      expect(adapter.bookmarks).to eq(bookmarks)
    end
  end

  describe 'port compliance' do
    it 'includes focused reader state ports' do
      expect(adapter).to be_a(Shoko::Core::Ports::Outbound::ReaderNavigationReader)
    end
  end
end
