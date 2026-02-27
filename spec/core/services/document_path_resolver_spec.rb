# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Core::Services::DocumentPathResolver do
  ResolverPayload = Struct.new(:source_path, keyword_init: true)
  ResolverDocument = Struct.new(:canonical_path, :source_path, :path, keyword_init: true)

  it 'resolves canonical path through cache pointer source path' do
    cache_pointer_resolver = instance_double('CachePointerResolver')
    path_ops = instance_double('PathOps')

    allow(cache_pointer_resolver).to receive(:cache_pointer?).with('/tmp/book.cache').and_return(true)
    allow(cache_pointer_resolver).to receive(:read_cache).with('/tmp/book.cache', strict: false)
      .and_return(ResolverPayload.new(source_path: '/books/source.epub'))
    allow(path_ops).to receive(:expand_path).with('/books/source.epub').and_return('/books/source.epub')

    resolver = described_class.new(
      cache_pointer_resolver: cache_pointer_resolver,
      path_ops: path_ops
    )

    expect(resolver.canonical_reader_path('/tmp/book.cache')).to eq('/books/source.epub')
  end

  it 'matches canonical document paths after expansion' do
    cache_pointer_resolver = instance_double('CachePointerResolver', cache_pointer?: false)
    path_ops = instance_double('PathOps')

    allow(path_ops).to receive(:expand_path).with('/books/source.epub').and_return('/books/source.epub')
    allow(path_ops).to receive(:expand_path).with('./books/source.epub').and_return('/books/source.epub')

    resolver = described_class.new(
      cache_pointer_resolver: cache_pointer_resolver,
      path_ops: path_ops
    )

    document = ResolverDocument.new(canonical_path: '/books/source.epub')
    expect(resolver.document_matches_path?(document, './books/source.epub')).to be(true)
  end

  it 'logs and falls back when cache pointer resolution fails' do
    cache_pointer_resolver = instance_double('CachePointerResolver')
    path_ops = instance_double('PathOps')
    logger = instance_double('Logger', debug: nil)

    allow(cache_pointer_resolver).to receive(:cache_pointer?).with('/tmp/bad.cache').and_return(true)
    allow(cache_pointer_resolver).to receive(:read_cache).with('/tmp/bad.cache', strict: false).and_raise(StandardError, 'boom')
    allow(path_ops).to receive(:expand_path).with('/tmp/bad.cache').and_return('/tmp/bad.cache')

    resolver = described_class.new(
      cache_pointer_resolver: cache_pointer_resolver,
      path_ops: path_ops,
      logger: logger
    )

    expect(resolver.canonical_reader_path('/tmp/bad.cache')).to eq('/tmp/bad.cache')
    expect(logger).to have_received(:debug).at_least(:once)
  end
end
