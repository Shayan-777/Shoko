# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Services::Reader::AnnotationStateService do
  let(:core_annotation_service) { instance_double('CoreAnnotationService') }
  let(:state_writer) { instance_double('StateWriter', update_reader: nil) }
  let(:logger) { instance_double('Logger', debug: nil) }
  let(:path) { '/tmp/book.epub' }
  let(:annotations) { [{ 'id' => 'a1' }] }

  subject(:service) do
    described_class.new(
      core_annotation_service: core_annotation_service,
      state_writer: state_writer,
      logger: logger
    )
  end

  it 'refreshes reader annotations after add' do
    annotation = { 'id' => 'a1' }

    expect(core_annotation_service).to receive(:add)
      .with(path, 'text', 'note', { start: 0, finish: 3 }, 1, nil)
      .and_return(annotation)
    expect(core_annotation_service).to receive(:list_for_book).with(path).and_return(annotations)
    expect(state_writer).to receive(:update_reader).with(annotations: annotations)

    result = service.add(path, 'text', 'note', { start: 0, finish: 3 }, 1)
    expect(result).to eq(annotation)
  end

  it 'refreshes reader annotations after update and delete' do
    expect(core_annotation_service).to receive(:update).with(path, 'a1', 'updated').and_return(true)
    expect(core_annotation_service).to receive(:list_for_book).with(path).and_return(annotations)
    expect(state_writer).to receive(:update_reader).with(annotations: annotations)

    expect(service.update(path, 'a1', 'updated')).to eq(true)

    expect(core_annotation_service).to receive(:delete).with(path, 'a1').and_return(true)
    expect(core_annotation_service).to receive(:list_for_book).with(path).and_return([])
    expect(state_writer).to receive(:update_reader).with(annotations: [])

    expect(service.delete(path, 'a1')).to eq(true)
  end

  it 'swallows refresh errors and preserves core return value' do
    expect(core_annotation_service).to receive(:update).with(path, 'a1', 'updated').and_return(true)
    expect(core_annotation_service).to receive(:list_for_book).with(path).and_raise(StandardError, 'boom')
    expect(logger).to receive(:debug).with(/annotation_state_service\.refresh failed/)

    expect(service.update(path, 'a1', 'updated')).to eq(true)
  end
end
