# frozen_string_literal: true

require 'spec_helper'
require 'shoko/application/services/annotations/chapter_stream_source'
require 'shoko/application/services/layout_service'

RSpec.describe Shoko::Application::Services::Annotations::ChapterStreamSource do
  let(:document) { double('document') }
  let(:layout_service) { Shoko::Application::Services::LayoutService.new }
  let(:terminal_size) { Struct.new(:width, :height).new(100, 40) }
  let(:runtime_context) { double('runtime_context', terminal_size: terminal_size) }
  let(:config_reader) { double('config', view_mode: :single, line_spacing: :normal) }

  let(:chapter_formatter) do
    formatter = Object.new
    formatter.extend(Shoko::Application::Ports::Outbound::ChapterFormatter)
    formatter
  end

  let(:line_wrapper) do
    wrapper = Object.new
    wrapper.extend(Shoko::Application::Ports::Outbound::LineWrapper)
    wrapper
  end

  def build_source(document_provider: -> { document }, wrapper: nil)
    described_class.new(
      document_provider: document_provider,
      chapter_formatter: chapter_formatter,
      layout_service: layout_service,
      reader_runtime_context: runtime_context,
      config_reader: config_reader,
      line_wrapper: wrapper
    )
  end

  it 'returns formatter-wrapped line text with a layout signature' do
    display_line = double('display_line', text: 'wrapped line')
    allow(chapter_formatter).to receive(:wrap_all) { [display_line, 'plain line'] }

    fetch = build_source.fetch(3)

    expect(fetch.lines).to eq(['wrapped line', 'plain line'])
    expect(fetch.signature).to include(3)
    expect(chapter_formatter).to have_received(:wrap_all) do |doc, chapter_index, width, config:, lines_per_page:|
      expect(doc).to be(document)
      expect(chapter_index).to eq(3)
      expect(width).to be_positive
      expect(config).to be(config_reader)
      expect(lines_per_page).to be_positive
    end
  end

  it 'falls back to the line wrapper over plain lines when formatting yields nothing' do
    allow(chapter_formatter).to receive(:wrap_all).and_return([])
    allow(chapter_formatter).to receive(:plain_lines_for).with(document, 1).and_return(['raw chapter line'])
    allow(line_wrapper).to receive(:wrap_lines).and_return(%w[wrapped raw])

    fetch = build_source(wrapper: line_wrapper).fetch(1)

    expect(fetch.lines).to eq(%w[wrapped raw])
    expect(line_wrapper).to have_received(:wrap_lines) do |plain, chapter_index, width, document: nil|
      expect(plain).to eq(['raw chapter line'])
      expect(chapter_index).to eq(1)
      expect(width).to be_positive
      expect(document).to be(self.document)
    end
  end

  it 'returns nil without a document' do
    expect(build_source(document_provider: -> {}).fetch(0)).to be_nil
  end

  it 'changes the signature when the layout changes' do
    allow(chapter_formatter).to receive(:wrap_all).and_return(['line'])
    source = build_source

    wide = source.fetch(0).signature
    terminal_size.width = 60
    narrow = source.fetch(0).signature

    expect(wide).not_to eq(narrow)
  end

  it 'rejects collaborators that do not implement the ports' do
    expect do
      described_class.new(
        document_provider: -> { document },
        chapter_formatter: Object.new,
        layout_service: layout_service,
        reader_runtime_context: runtime_context,
        config_reader: config_reader
      )
    end.to raise_error(ArgumentError, /ChapterFormatter/)
  end
end
