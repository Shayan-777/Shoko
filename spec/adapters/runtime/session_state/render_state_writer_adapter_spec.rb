# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Runtime::SessionState::RenderStateWriterAdapter do
  let(:state) { instance_double('StateStore') }
  let(:logger) { instance_double('Logger') }
  let(:adapter) { described_class.new(state, logger: logger) }

  before do
    allow(state).to receive(:dispatch)
  end

  describe '#clear_rendered_lines' do
    it 'dispatches ClearRenderedLinesAction' do
      expect(state).to receive(:dispatch).with(instance_of(Shoko::Adapters::Runtime::SessionState::Actions::ClearRenderedLinesAction))
      adapter.clear_rendered_lines
    end

    context 'when dispatch raises an error' do
      before do
        allow(state).to receive(:dispatch).and_raise(StandardError.new('dispatch failed'))
        allow(logger).to receive(:error)
      end

      it 'logs the error instead of raising' do
        expect(logger).to receive(:error).with(
          'render_state_writer.clear_rendered_lines_failed',
          hash_including(error: 'StandardError', message: 'dispatch failed')
        )
        expect { adapter.clear_rendered_lines }.not_to raise_error
      end
    end
  end

  describe '#update_rendered_lines' do
    let(:rendered_lines) { { left: { 1 => 'line 1' }, right: { 1 => 'line 2' } } }

    it 'dispatches UpdateRenderedLinesAction with the lines' do
      expect(state).to receive(:dispatch).with(instance_of(Shoko::Adapters::Runtime::SessionState::Actions::UpdateRenderedLinesAction))
      adapter.update_rendered_lines(rendered_lines)
    end

    context 'when dispatch raises an error' do
      before do
        allow(state).to receive(:dispatch).and_raise(StandardError.new('update failed'))
        allow(logger).to receive(:error)
      end

      it 'logs the error instead of raising' do
        expect(logger).to receive(:error).with(
          'render_state_writer.update_rendered_lines_failed',
          hash_including(error: 'StandardError', message: 'update failed')
        )
        expect { adapter.update_rendered_lines(rendered_lines) }.not_to raise_error
      end
    end
  end

  describe 'port compliance' do
    it 'includes RenderStateWriter port' do
      expect(adapter).to be_a(Shoko::Core::Ports::Outbound::RenderStateWriter)
    end
  end
end
