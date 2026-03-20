# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'

RSpec.describe Shoko::Adapters::Storage::Repositories::Storage::AnnotationFileStore do
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

    expect(store.add('book.epub', 't1', 'n1', { 'start' => 0, 'end' => 1 }, 0)).to include('text' => 't1')
    expect(store.add('book.epub', 't2', 'n2', { 'start' => 2, 'end' => 3 }, 0)).to include('text' => 't2')

    ids = store.get('book.epub').map { |annotation| annotation[:id] }
    expect(ids.size).to eq(2)
    expect(ids.uniq.size).to eq(2)
  end
end
