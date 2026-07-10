# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'json'

RSpec.describe Shoko::Adapters::Storage::Repositories::Storage::AnnotationFileStore do
  def build_draft(text:, note:, chapter_index:, anchor: nil)
    Shoko::Core::Models::AnnotationDraft.new(
      text: text,
      note: note,
      anchor: anchor,
      chapter_index: chapter_index
    )
  end

  let(:file_writer) do
    writer = Object.new
    writer.define_singleton_method(:write) do |path, data|
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, data)
      true
    end
    writer
  end

  around do |example|
    Dir.mktmpdir do |dir|
      with_env('XDG_CONFIG_HOME' => dir) { example.run }
    end
  end

  it 'generates unique ids even when entries share the same timestamp' do
    fixed_now = Time.utc(2026, 1, 1, 0, 0, 0, 123_456)
    allow(Time).to receive(:now).and_return(fixed_now)
    store = described_class.new(file_writer: file_writer)
    first_draft = build_draft(text: 't1', note: 'n1', anchor: { quote: 't1' }, chapter_index: 0)
    second_draft = build_draft(text: 't2', note: 'n2', anchor: { quote: 't2' }, chapter_index: 0)

    expect(store.add('book.epub', first_draft)).to include('text' => 't1')
    expect(store.add('book.epub', second_draft)).to include('text' => 't2')

    ids = store.get('book.epub').map { |annotation| annotation[:id] }
    expect(ids.size).to eq(2)
    expect(ids.uniq.size).to eq(2)
  end

  it 'persists the document anchor and migrates legacy range/page records on read' do
    store = described_class.new(file_writer: file_writer)
    store.add('book.epub', build_draft(text: 'quote', note: 'n', anchor: { quote: 'quote', position: 0.5 },
                                       chapter_index: 1))

    stored = store.get('book.epub').first
    expect(stored[:anchor]).to include(quote: 'quote', position: 0.5)
    expect(stored).not_to have_key(:range)

    legacy = { 'id' => 'old', 'text' => 'legacy quote', 'note' => 'n', 'chapter_index' => 2,
               'range' => { 'start' => { 'geometry_key' => 'x' } }, 'page_offset' => 4 }
    File.write(
      File.join(ENV.fetch('XDG_CONFIG_HOME'), 'shoko', 'annotations.json'),
      JSON.generate('other.epub' => [legacy])
    )

    migrated = store.get('other.epub').first
    expect(migrated[:anchor]).to eq(quote: 'legacy quote')
    expect(migrated).not_to have_key(:range)
    expect(migrated).not_to have_key(:page_offset)
  end

  it 'rejects non-draft writes' do
    store = described_class.new(file_writer: file_writer)

    expect do
      store.add('book.epub', { text: 't1' })
    end.to raise_error(ArgumentError, /draft must be/)
  end

  # A corrupt/truncated/externally-synced annotations.json must not block
  # opening the book: reads degrade to empty (and a later write heals the file).
  def write_store(content)
    path = File.join(ENV.fetch('XDG_CONFIG_HOME'), 'shoko', 'annotations.json')
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  it 'degrades to empty when the store file is not valid JSON' do
    write_store('{ this is not: valid json ]')
    store = described_class.new(file_writer: file_writer)

    expect(store.get('book.epub')).to eq([])
    expect(store.all).to eq({})
  end

  it 'degrades to empty when the store file is valid JSON of the wrong shape' do
    write_store(JSON.generate(%w[unexpected array payload]))
    store = described_class.new(file_writer: file_writer)

    expect(store.all).to eq({})
  end

  it 'keeps writing usable after a corrupt read (the next add heals the file)' do
    write_store('not json at all')
    store = described_class.new(file_writer: file_writer)

    store.add('book.epub', build_draft(text: 't', note: 'n', anchor: { quote: 't' }, chapter_index: 0))

    expect(store.get('book.epub').map { |a| a[:text] }).to eq(['t'])
  end

  it 'quarantines a corrupt store so pre-corruption bytes survive the healing write' do
    # A sync conflict (Dropbox/rsync, a second instance) leaves annotations.json
    # corrupt but still carrying the user's data. Opening the book heals the
    # file on the next save; the corrupt original must be preserved for
    # recovery, never silently clobbered.
    corrupt = '{"book.epub": [ truncated by a sync conflict'
    write_store(corrupt)
    store = described_class.new(file_writer: file_writer)

    store.add('other.epub', build_draft(text: 'new', note: 'n', anchor: { quote: 'new' }, chapter_index: 0))

    quarantines = Dir.glob(File.join(ENV.fetch('XDG_CONFIG_HOME'), 'shoko', 'annotations.json.corrupt-*'))
    expect(quarantines.size).to eq(1)
    expect(File.read(quarantines.first)).to eq(corrupt)
    expect(store.get('other.epub').map { |annotation| annotation[:text] }).to eq(['new'])
  end

  it 'does not lose updates when two threads mutate concurrently' do
    # Every mutation runs its whole read-modify-write under the sidecar
    # flock; without it, two adds can read the same baseline and one
    # annotation silently vanishes.
    store = described_class.new(file_writer: Shoko::Adapters::Storage::AtomicFileWriter)
    adds_per_thread = 5
    barrier = Queue.new
    threads = 2.times.map do |thread_index|
      Thread.new do
        barrier.pop
        adds_per_thread.times do |i|
          store.add('book.epub', build_draft(text: "t#{thread_index}-#{i}", note: 'n', chapter_index: 0))
        end
      end
    end
    2.times { barrier << true }
    threads.each(&:join)

    expect(store.get('book.epub').length).to eq(2 * adds_per_thread)
  end

  it 'aborts a mutation on an access error instead of flattening the store' do
    # A transiently unreadable file (permissions, remounting disk) must fail
    # the add loudly; degrading to an empty baseline here would let the save
    # destroy every annotation the user ever made.
    store = described_class.new(file_writer: file_writer)
    store.add('book.epub', build_draft(text: 'precious', note: 'n', chapter_index: 0))
    path = File.join(ENV.fetch('XDG_CONFIG_HOME'), 'shoko', 'annotations.json')
    allow(File).to receive(:read).with(path).and_raise(Errno::EACCES)

    expect do
      store.add('other.epub', build_draft(text: 'new', note: 'n', chapter_index: 0))
    end.to raise_error(Shoko::StorageError)

    allow(File).to receive(:read).with(path).and_call_original
    expect(store.get('book.epub').map { |a| a[:text] }).to eq(['precious'])
  end

  it 'persists annotations in a versioned envelope' do
    store = described_class.new(file_writer: file_writer)
    store.add('book.epub', build_draft(text: 't', note: 'n', anchor: { quote: 't' }, chapter_index: 0))

    raw = JSON.parse(File.read(File.join(ENV.fetch('XDG_CONFIG_HOME'), 'shoko', 'annotations.json')))
    expect(raw['schema_version']).to eq(2)
    expect(raw['entries']).to have_key('book.epub')
    expect(raw['entries']['book.epub'].first).to include('anchor' => { 'quote' => 't' })
  end

  it 'rewrites legacy range/page records into the v2 schema on the next save' do
    legacy = { 'id' => 'old', 'text' => 'legacy quote', 'note' => 'n', 'chapter_index' => 2,
               'range' => { 'start' => { 'geometry_key' => 'x' } }, 'page_offset' => 4 }
    write_store(JSON.generate('book.epub' => [legacy]))
    store = described_class.new(file_writer: file_writer)

    # Any write flows the load-time upgrade into the persisted file.
    store.add('book.epub', build_draft(text: 'new', note: 'n', anchor: { quote: 'new' }, chapter_index: 0))

    raw = JSON.parse(File.read(File.join(ENV.fetch('XDG_CONFIG_HOME'), 'shoko', 'annotations.json')))
    expect(raw['schema_version']).to eq(2)
    persisted_legacy = raw['entries']['book.epub'].find { |record| record['id'] == 'old' }
    expect(persisted_legacy['anchor']).to eq('quote' => 'legacy quote')
    expect(persisted_legacy).not_to have_key('range')
    expect(persisted_legacy).not_to have_key('page_offset')
  end
end
