# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Runtime::SessionState::RenderStateWriterAdapter do
  let(:state) { instance_double('StateStore') }
  let(:render_registry) { instance_double('RenderRegistry') }
  let(:logger) { instance_double('Logger') }
  let(:adapter) { described_class.new(state, render_registry: render_registry, logger: logger) }

  describe '#clear_rendered_lines' do
    it 'clears the render registry' do
      expect(render_registry).to receive(:clear)
      adapter.clear_rendered_lines
    end

    context 'when the render registry raises an error' do
      before do
        allow(render_registry).to receive(:clear).and_raise(Shoko::StateUpdateError.new('clear failed'))
        allow(logger).to receive(:error)
      end

      it 'logs and re-raises the error' do
        expect(logger).to receive(:error).with(
          'render_state_writer.clear_rendered_lines_failed',
          hash_including(error: 'Shoko::StateUpdateError', message: a_string_including('clear failed'))
        )
        expect { adapter.clear_rendered_lines }.to raise_error(Shoko::StateUpdateError, /clear failed/)
      end
    end
  end

  describe '#update_rendered_lines' do
    let(:rendered_lines) { { left: { 1 => 'line 1' }, right: { 1 => 'line 2' } } }

    it 'writes rendered lines to the render registry' do
      expect(render_registry).to receive(:write).with(rendered_lines)
      adapter.update_rendered_lines(rendered_lines)
    end

    context 'when the render registry raises an error' do
      before do
        allow(render_registry).to receive(:write).with(rendered_lines).and_raise(Shoko::StateUpdateError.new('update failed'))
        allow(logger).to receive(:error)
      end

      it 'logs and re-raises the error' do
        expect(logger).to receive(:error).with(
          'render_state_writer.update_rendered_lines_failed',
          hash_including(error: 'Shoko::StateUpdateError', message: a_string_including('update failed'))
        )
        expect { adapter.update_rendered_lines(rendered_lines) }.to raise_error(Shoko::StateUpdateError, /update failed/)
      end
    end
  end
end
