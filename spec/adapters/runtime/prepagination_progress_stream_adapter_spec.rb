# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require 'shoko/adapters/runtime/prepagination_progress_stream_adapter'

RSpec.describe Shoko::Adapters::Runtime::PrepaginationProgressStreamAdapter do
  let(:output) { StringIO.new }

  subject(:writer) { described_class.new(output: output) }

  it 'emits one JSON line per event' do
    writer.start(total: 2, paths: ['/books/a.epub', '/books/b.epub'])
    writer.report(done: 1)
    writer.finish

    events = output.string.lines.map { |line| JSON.parse(line) }
    expect(events).to eq(
      [
        { 'event' => 'start', 'total' => 2, 'paths' => ['/books/a.epub', '/books/b.epub'] },
        { 'event' => 'report', 'done' => 1 },
        { 'event' => 'finish' },
      ]
    )
  end

  it 'swallows pipe errors so a cancelled parent never aborts pagination' do
    closed = StringIO.new
    closed.close
    broken = described_class.new(output: closed)

    expect { broken.report(done: 1) }.not_to raise_error
  end
end
