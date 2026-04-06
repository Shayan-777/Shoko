# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'

RSpec.describe Shoko::Adapters::Storage::Repositories::Storage::AnnotationFileStore do
  def build_draft(text:, note:, range:, chapter_index:, page_meta: nil)
    Shoko::Core::Models::AnnotationDraft.new(
      text: text,
      note: note,
      range: range,
      chapter_index: chapter_index,
      page_meta: page_meta
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
    first_draft = build_draft(text: 't1', note: 'n1', range: { 'start' => 0, 'end' => 1 }, chapter_index: 0)
    second_draft = build_draft(text: 't2', note: 'n2', range: { 'start' => 2, 'end' => 3 }, chapter_index: 0)

    expect(store.add('book.epub', first_draft)).to include('text' => 't1')
    expect(store.add('book.epub', second_draft)).to include('text' => 't2')

    ids = store.get('book.epub').map { |annotation| annotation[:id] }
    expect(ids.size).to eq(2)
    expect(ids.uniq.size).to eq(2)
  end

  it 'rejects non-draft writes' do
    store = described_class.new(file_writer: file_writer)

    expect do
      store.add('book.epub', { text: 't1' })
    end.to raise_error(ArgumentError, /draft must be/)
  end
end
