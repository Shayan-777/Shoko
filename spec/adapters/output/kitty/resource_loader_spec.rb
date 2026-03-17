# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Output::Kitty::ResourceLoader do
  let(:loader_class) do
    Class.new do
      class << self
        def resolve_chapter_relative(chapter_entry_path, src)
          "#{chapter_entry_path}|#{src}"
        end
      end

      attr_reader :fetch_calls

      def initialize
        @fetch_calls = []
      end

      def fetch(**kwargs)
        @fetch_calls << kwargs
        'bytes'
      end

      def store(**); end

      def cached?(**)
        false
      end
    end
  end

  it 'passes through fetch without requiring cache_key' do
    loader = loader_class.new
    resource_loader = described_class.new(loader: loader)

    result = resource_loader.fetch(
      book_sha: 'a' * 64,
      epub_path: '/tmp/book.epub',
      entry_path: 'OPS/images/a.jpg',
      persist: true
    )

    expect(result).to eq('bytes')
    expect(loader.fetch_calls).to eq(
      [
        {
          book_sha: 'a' * 64,
          epub_path: '/tmp/book.epub',
          entry_path: 'OPS/images/a.jpg',
          cache_key: nil,
          persist: true,
        },
      ]
    )
  end
end
