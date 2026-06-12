# frozen_string_literal: true

require 'spec_helper'

# Snappiness guardrail: the library pre-pagination batch must never run on a
# thread inside the menu process. Pagination is CPU-bound; under the GIL even
# a low-priority thread starves the render loop (measured at ~6x press->paint
# latency and multi-second screen freezes before the 2026-06 fix; see
# script/bench/menu_responsiveness_benchmark.rb for the harness that proves
# it). The warmup may only supervise an out-of-process batch through the
# PrepaginationBatchRunner port.
RSpec.describe 'Pre-pagination process isolation' do
  let(:lib_root) { File.expand_path('../../../lib/shoko', __dir__) }
  let(:warmup_source) do
    File.read(File.join(lib_root, 'application/workflows/menu/library_prepagination_warmup.rb'))
  end

  it 'keeps page-map building out of the menu-process warmup' do
    expect(warmup_source).not_to match(/build_dynamic_map!|build_absolute_map!|document_loader|page_calculator/),
                                 'LibraryPrepaginationWarmup must supervise the batch child via ' \
                                 'PrepaginationBatchRunner, never paginate in-process (GIL starvation)'
  end

  it 'supervises through the batch-runner port' do
    expect(warmup_source).to include('PrepaginationBatchRunner')
  end

  it 'wires the warmup to the out-of-process batch runner' do
    registration = File.read(
      File.join(lib_root, 'composition/container_factory/domain_application_registration.rb')
    )
    expect(registration).to include('PrepaginationBatchProcessAdapter')
  end
end
