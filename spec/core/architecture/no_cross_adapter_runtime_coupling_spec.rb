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

  it 'forbids document loader adapter from direct storage pipeline construction' do
    path = File.join(lib_root, 'adapters', 'book_sources', 'document_loader_adapter.rb')
    content = File.read(path)

    expect(content).not_to match(/\bAdapters::Storage::BookCachePipeline\b/),
                           'DocumentLoaderAdapter must resolve cache pipeline through Core::Ports::Outbound::BookCachePipelineFactory'
  end
end
