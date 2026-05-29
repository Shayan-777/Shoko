# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Render registry boundary guardrails' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:reader_snapshot_path) do
    File.join(root, 'lib', 'shoko', 'application', 'ports', 'outbound', 'state', 'reader_snapshot.rb')
  end
  let(:reader_view_schema_path) do
    File.join(root, 'lib', 'shoko', 'application', 'state', 'schema', 'reader_view.rb')
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

  it 'keeps rendered_lines out of the reader snapshot contract' do
    expect(Shoko::Application::Ports::Outbound::State::ReaderSnapshot::FIELDS).not_to include(:rendered_lines),
                                                                                      "ReaderSnapshot FIELDS must not expose rendered_lines once render geometry is adapter-owned: #{reader_snapshot_path}"
  end

  it 'keeps rendered_lines out of layered schema fragments' do
    offenders = []
    offenders << 'reader_view_schema.rb' if non_comment_content(reader_view_schema_path).include?('rendered_lines:')

    expect(offenders).to eq([]),
                         "Rendered geometry must not live in layered schemas:\n#{offenders.join("\n")}"
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
