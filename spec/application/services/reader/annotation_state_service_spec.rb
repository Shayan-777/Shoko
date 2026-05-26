# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../lib/shoko/core/models/annotation_draft'

class AnnotationStateServiceTestReaderSessionStore
  include Shoko::Application::Ports::Outbound::ReaderSessionStore

  attr_reader :snapshot

  def initialize(snapshot)
    @snapshot = snapshot
  end

  def load
    @snapshot
  end

  def save(snapshot)
    @snapshot = snapshot
  end
end

RSpec.describe Shoko::Application::Services::Reader::AnnotationStateService do
  let(:core_annotation_service) { instance_double('CoreAnnotationService') }
  let(:reader_session_store) do
    AnnotationStateServiceTestReaderSessionStore.new(Shoko::Core::Models::Session::ReaderSnapshot.build)
  end
  let(:logger) { instance_double('Logger', debug: nil) }
  let(:path) { '/tmp/book.epub' }
  let(:annotations) { [{ 'id' => 'a1' }] }

  subject(:service) do
    described_class.new(
      core_annotation_service: core_annotation_service,
      reader_session_store: reader_session_store,
      logger: logger
    )
  end

  it 'refreshes reader annotations after add' do
    annotation = { 'id' => 'a1' }
    draft = Shoko::Core::Models::AnnotationDraft.new(
      text: 'text',
      note: 'note',
      range: { start: 0, finish: 3 },
      chapter_index: 1,
      page_meta: nil
    )

    expect(core_annotation_service).to receive(:add)
      .with(path, draft)
      .and_return(annotation)
    expect(core_annotation_service).to receive(:list_for_book).with(path).and_return(annotations)

    result = service.add(path, draft)
    expect(result).to eq(annotation)
    expect(reader_session_store.load.annotations).to eq(annotations)
  end

  it 'refreshes reader annotations after update and delete' do
    updated = { id: 'a1', note: 'updated' }
    deleted = { id: 'a1' }

    expect(core_annotation_service).to receive(:update).with(path, 'a1', 'updated').and_return(updated)
    expect(core_annotation_service).to receive(:list_for_book).with(path).and_return(annotations)

    expect(service.update(path, 'a1', 'updated')).to eq(updated)
    expect(reader_session_store.load.annotations).to eq(annotations)

    expect(core_annotation_service).to receive(:delete).with(path, 'a1').and_return(deleted)
    expect(core_annotation_service).to receive(:list_for_book).with(path).and_return([])

    expect(service.delete(path, 'a1')).to eq(deleted)
    expect(reader_session_store.load.annotations).to eq([])
  end

  it 'fails fast when refresh raises' do
    expect(core_annotation_service).to receive(:update).with(path, 'a1', 'updated').and_return({ id: 'a1' })
    expect(core_annotation_service).to receive(:list_for_book).with(path).and_raise(StandardError, 'boom')

    expect { service.update(path, 'a1', 'updated') }.to raise_error(StandardError, 'boom')
  end

  it 'rejects non-draft annotation creation payloads' do
    expect do
      service.add(path, { text: 'text' })
    end.to raise_error(ArgumentError, /draft must be/)
  end
end
