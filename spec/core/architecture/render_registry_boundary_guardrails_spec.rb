# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Render registry boundary guardrails' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:reader_snapshot_path) { File.join(root, 'lib', 'shoko', 'core', 'models', 'session', 'reader_snapshot.rb') }
  let(:initial_state_builder_path) do
    File.join(root, 'lib', 'shoko', 'adapters', 'runtime', 'session_state', 'state_store', 'initial_state_builder.rb')
  end
  let(:reader_selectors_path) do
    File.join(root, 'lib', 'shoko', 'adapters', 'runtime', 'session_state', 'selectors', 'reader_selectors.rb')
  end
  let(:rendered_content_reader_path) do
    File.join(root, 'lib', 'shoko', 'adapters', 'runtime', 'session_state', 'rendered_content_reader_adapter.rb')
  end
  let(:render_state_writer_path) do
    File.join(root, 'lib', 'shoko', 'adapters', 'runtime', 'session_state', 'render_state_writer_adapter.rb')
  end
  let(:legacy_action_path) do
    File.join(root, 'lib', 'shoko', 'adapters', 'runtime', 'session_state', 'actions', 'update_rendered_lines_action.rb')
  end

  def non_comment_content(path)
    File.readlines(path).reject { |line| line.strip.start_with?('#') }.join
  rescue Errno::ENOENT
    ''
  end

  it 'keeps rendered_lines out of the core reader snapshot contract' do
    expect(Shoko::Core::Models::Session::ReaderSnapshotFields).not_to include(:rendered_lines),
      "ReaderSnapshotFields must not expose rendered_lines once render geometry is adapter-owned: #{reader_snapshot_path}"
  end

  it 'keeps rendered_lines out of state initialization and selectors' do
    offenders = []
    offenders << 'initial_state_builder.rb' if non_comment_content(initial_state_builder_path).include?('rendered_lines:')
    offenders << 'reader_selectors.rb' if non_comment_content(reader_selectors_path).match?(/def\s+rendered_lines\b/)

    expect(offenders).to eq([]),
      "Rendered geometry must not live in state initialization or state selectors:\n#{offenders.join("\n")}"
  end

  it 'forbids legacy state-backed rendered-lines shims from reappearing' do
    reader_content = non_comment_content(rendered_content_reader_path)
    writer_content = non_comment_content(render_state_writer_path)

    expect(File.exist?(legacy_action_path)).to be(false),
      "Legacy rendered-lines state action must stay deleted: #{legacy_action_path}"
    expect(reader_content).not_to include('ReaderSelectors.rendered_lines'),
      "RenderedContentReaderAdapter must read from the render registry directly: #{rendered_content_reader_path}"
    expect(reader_content).not_to include('%i[reader rendered_lines]'),
      "RenderedContentReaderAdapter must not fall back to reader state: #{rendered_content_reader_path}"
    expect(writer_content).not_to include('dispatch('),
      "RenderStateWriterAdapter must not publish render geometry into the state store: #{render_state_writer_path}"
  end
end
