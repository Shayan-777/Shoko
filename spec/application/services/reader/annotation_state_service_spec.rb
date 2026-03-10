# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Services::Reader::AnnotationStateService do
  class AnnotationStateServiceTestReaderSessionStore
    include Shoko::Core::Ports::Outbound::ReaderSessionStore

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

    expect(core_annotation_service).to receive(:add)
      .with(path, 'text', 'note', { start: 0, finish: 3 }, 1, nil)
      .and_return(annotation)
    expect(core_annotation_service).to receive(:list_for_book).with(path).and_return(annotations)

    result = service.add(path, 'text', 'note', { start: 0, finish: 3 }, 1)
    expect(result).to eq(annotation)
    expect(reader_session_store.load.annotations).to eq(annotations)
  end

  it 'refreshes reader annotations after update and delete' do
    expect(core_annotation_service).to receive(:update).with(path, 'a1', 'updated').and_return(true)
    expect(core_annotation_service).to receive(:list_for_book).with(path).and_return(annotations)

    expect(service.update(path, 'a1', 'updated')).to eq(true)
    expect(reader_session_store.load.annotations).to eq(annotations)

    expect(core_annotation_service).to receive(:delete).with(path, 'a1').and_return(true)
    expect(core_annotation_service).to receive(:list_for_book).with(path).and_return([])

    expect(service.delete(path, 'a1')).to eq(true)
    expect(reader_session_store.load.annotations).to eq([])
  end

  it 'fails fast when refresh raises' do
    expect(core_annotation_service).to receive(:update).with(path, 'a1', 'updated').and_return(true)
    expect(core_annotation_service).to receive(:list_for_book).with(path).and_raise(StandardError, 'boom')

    expect { service.update(path, 'a1', 'updated') }.to raise_error(StandardError, 'boom')
  end
end
