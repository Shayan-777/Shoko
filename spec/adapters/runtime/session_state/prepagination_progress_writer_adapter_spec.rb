# frozen_string_literal: true

require 'spec_helper'
require 'shoko/adapters/runtime/session_state/prepagination_progress_writer_adapter'

RSpec.describe Shoko::Adapters::Runtime::SessionState::PrepaginationProgressWriterAdapter do
  let(:state) { instance_double(Shoko::Application::State::StateStore) }

  subject(:writer) { described_class.new(state) }

  # Each call writes only the prepagination paths (never a full menu snapshot),
  # which is what keeps it safe to call from the warmup worker thread without
  # clobbering concurrent menu-state edits on the main thread.
  it 'starts a batch by narrowly setting active/total/done and the per-book queue' do
    expect(state).to receive(:update).with(
      %i[menu prepaginate_active] => true,
      %i[menu prepaginate_total] => 5,
      %i[menu prepaginate_done] => 0,
      %i[menu prepaginate_paths] => ['/books/a.epub', '/books/b.epub']
    )

    writer.start(total: 5, paths: ['/books/a.epub', '/books/b.epub'])
  end

  it 'reports progress as a single narrow done update' do
    expect(state).to receive(:update).with(%i[menu prepaginate_done] => 3)

    writer.report(done: 3)
  end

  it 'finishes by clearing the toast fields' do
    expect(state).to receive(:update).with(
      %i[menu prepaginate_active] => false,
      %i[menu prepaginate_total] => 0,
      %i[menu prepaginate_done] => 0,
      %i[menu prepaginate_paths] => []
    )

    writer.finish
  end
end
