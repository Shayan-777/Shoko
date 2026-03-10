# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Storage::ReaderDocumentLocator do
  ResolverPayload = Struct.new(:source_path, keyword_init: true)
  class ResolverDocument
    include Shoko::Core::Ports::Outbound::ReaderDocument

    attr_reader :canonical_path

    def initialize(canonical_path:)
      @canonical_path = canonical_path
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

    def toc_entries
      []
    end
  end

  class CachePointerResolverDouble
    include Shoko::Core::Ports::Outbound::CachePointerResolver

    def initialize(cache_pointer_proc:, read_cache_proc:)
      @cache_pointer_proc = cache_pointer_proc
      @read_cache_proc = read_cache_proc
    end

    def cache_pointer?(path)
      @cache_pointer_proc.call(path)
    end

    def read_cache(path, strict: false)
      @read_cache_proc.call(path, strict)
    end
  end

  class PathOpsDouble
    include Shoko::Core::Ports::Outbound::PathOps

    def initialize(expand_proc:)
      @expand_proc = expand_proc
    end

    def expand_path(path, dir = nil)
      @expand_proc.call(path, dir)
    end

    def join(*parts)
      File.join(*parts)
    end

    def basename(path)
      File.basename(path)
    end

    def extname(path)
      File.extname(path)
    end
  end

  it 'resolves canonical path through cache pointer source path' do
    cache_pointer_resolver = CachePointerResolverDouble.new(
      cache_pointer_proc: ->(path) { path == '/tmp/book.cache' },
      read_cache_proc: ->(path, strict) {
        if path == '/tmp/book.cache' && strict == false
          ResolverPayload.new(source_path: '/books/source.epub')
        else
          nil
        end
      }
    )
    path_ops = PathOpsDouble.new(expand_proc: ->(path, _dir) { path })

    resolver = described_class.new(
      cache_pointer_resolver: cache_pointer_resolver,
      path_ops: path_ops
    )

    expect(resolver.canonical_reader_path('/tmp/book.cache')).to eq('/books/source.epub')
  end

  it 'matches canonical document paths after expansion' do
    cache_pointer_resolver = CachePointerResolverDouble.new(
      cache_pointer_proc: ->(_path) { false },
      read_cache_proc: ->(_path, _strict) { nil }
    )
    path_ops = PathOpsDouble.new(
      expand_proc: lambda { |path, _dir|
        path == './books/source.epub' ? '/books/source.epub' : path
      }
    )

    resolver = described_class.new(
      cache_pointer_resolver: cache_pointer_resolver,
      path_ops: path_ops
    )

    document = ResolverDocument.new(canonical_path: '/books/source.epub')
    expect(resolver.document_matches_path?(document, './books/source.epub')).to be(true)
  end

  it 'raises when cache pointer resolution fails' do
    cache_pointer_resolver = CachePointerResolverDouble.new(
      cache_pointer_proc: ->(path) { path == '/tmp/bad.cache' },
      read_cache_proc: lambda { |path, strict|
        raise StandardError, 'boom' if path == '/tmp/bad.cache' && strict == false

        nil
      }
    )
    path_ops = PathOpsDouble.new(expand_proc: ->(path, _dir) { path })
    resolver = described_class.new(
      cache_pointer_resolver: cache_pointer_resolver,
      path_ops: path_ops
    )

    expect { resolver.canonical_reader_path('/tmp/bad.cache') }.to raise_error(StandardError, 'boom')
  end
end
