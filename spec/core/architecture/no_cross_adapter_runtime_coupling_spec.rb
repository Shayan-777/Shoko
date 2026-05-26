# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'No cross-adapter runtime coupling' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:lib_root) { File.join(root, 'lib', 'shoko') }

  def rel(path)
    path.delete_prefix("#{root}/")
  end

  it 'forbids output adapters from referencing runtime adapter namespace directly' do
    output_root = File.join(lib_root, 'adapters', 'output')
    offenders = Dir[File.join(output_root, '**', '*.rb')].filter_map do |path|
      next unless File.read(path).match?(/\bAdapters::Runtime::/)

      rel(path)
    end

    expect(offenders).to eq([]),
                         "Output adapters must depend on outbound ports/shared abstractions, not Adapters::Runtime:\n#{offenders.join("\n")}"
  end

  it 'keeps the legacy book-source document loader adapter deleted' do
    path = File.join(lib_root, 'adapters', 'book_sources', 'document_loader_adapter.rb')

    expect(File.exist?(path)).to eq(false),
                                "Document loading orchestration belongs in application, not #{rel(path)}"
  end

  it 'forbids storage adapters from referencing book-source or output adapters' do
    storage_root = File.join(lib_root, 'adapters', 'storage')
    offenders = Dir[File.join(storage_root, '**', '*.rb')].filter_map do |path|
      content = File.read(path)
      next unless content.match?(/\bAdapters::(?:BookSources|Output)::|adapters\/(?:book_sources|output)\//)

      rel(path)
    end

    expect(offenders).to eq([]),
                         "Storage adapters must not call sibling adapters:\n#{offenders.join("\n")}"
  end
end
