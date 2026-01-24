# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Core::Ports::ReaderStateReader do
  let(:implementation) do
    Class.new do
      include Shoko::Core::Ports::ReaderStateReader
    end.new
  end

  describe 'port interface' do
    it 'defines #current_chapter' do
      expect { implementation.current_chapter }.to raise_error(NotImplementedError)
    end

    it 'defines #total_chapters' do
      expect { implementation.total_chapters }.to raise_error(NotImplementedError)
    end

    it 'defines #current_page_index' do
      expect { implementation.current_page_index }.to raise_error(NotImplementedError)
    end

    it 'defines #left_page' do
      expect { implementation.left_page }.to raise_error(NotImplementedError)
    end

    it 'defines #right_page' do
      expect { implementation.right_page }.to raise_error(NotImplementedError)
    end

    it 'defines #single_page' do
      expect { implementation.single_page }.to raise_error(NotImplementedError)
    end

    it 'defines #current_page' do
      expect { implementation.current_page }.to raise_error(NotImplementedError)
    end

    it 'defines #page_map' do
      expect { implementation.page_map }.to raise_error(NotImplementedError)
    end

    it 'defines #book_path' do
      expect { implementation.book_path }.to raise_error(NotImplementedError)
    end

    it 'defines #bookmarks' do
      expect { implementation.bookmarks }.to raise_error(NotImplementedError)
    end
  end
end
