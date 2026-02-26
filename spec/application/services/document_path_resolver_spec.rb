# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Services::DocumentPathResolver do
  ResolverPayload = Struct.new(:source_path, keyword_init: true)
  ResolverDocument = Struct.new(:canonical_path, keyword_init: true)

  class ResolverHost
    include Shoko::Application::Services::DocumentPathResolver

    def initialize(cache_pointer_resolver:, path_ops:, logger: nil, logger_ref: nil)
      @cache_pointer_resolver = cache_pointer_resolver
      @path_ops = path_ops
      @logger = logger
      @logger_ref = logger_ref
    end
  end

  it 'resolves canonical paths and document matching with @logger host convention' do
    resolver = instance_double('CachePointerResolver')
    path_ops = instance_double('PathOps')
    logger = instance_double('Logger', debug: nil)

    allow(resolver).to receive(:cache_pointer?).with('/tmp/book.cache').and_return(true)
    allow(resolver).to receive(:read_cache).with('/tmp/book.cache', strict: false)
      .and_return(ResolverPayload.new(source_path: '/books/source.epub'))
    allow(path_ops).to receive(:expand_path).with('/books/source.epub').and_return('/books/source.epub')
    allow(path_ops).to receive(:expand_path).with('/tmp/book.cache').and_return('/tmp/book.cache')

    host = ResolverHost.new(cache_pointer_resolver: resolver, path_ops: path_ops, logger: logger)
    canonical = host.canonical_reader_path('/tmp/book.cache')

    expect(canonical).to eq('/books/source.epub')
    expect(host.document_matches_path?(ResolverDocument.new(canonical_path: '/books/source.epub'), '/books/source.epub')).to be(true)
  end

  it 'supports @logger_ref host convention for debug logging on resolution errors' do
    resolver = instance_double('CachePointerResolver')
    path_ops = instance_double('PathOps')
    logger_ref = instance_double('Logger', debug: nil)

    allow(resolver).to receive(:cache_pointer?).with('/tmp/bad.cache').and_return(true)
    allow(resolver).to receive(:read_cache).with('/tmp/bad.cache', strict: false).and_raise(StandardError, 'boom')
    allow(path_ops).to receive(:expand_path).with('/tmp/bad.cache').and_return('/tmp/bad.cache')

    host = ResolverHost.new(cache_pointer_resolver: resolver, path_ops: path_ops, logger_ref: logger_ref)
    canonical = host.canonical_reader_path('/tmp/bad.cache')

    expect(canonical).to eq('/tmp/bad.cache')
    expect(logger_ref).to have_received(:debug).at_least(:once)
  end
end
