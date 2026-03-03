# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Runtime::SessionState::ReaderLaunchStateAdapter do
  subject(:adapter) { described_class.new }

  it 'stores and clears the preloaded document' do
    document = instance_double('Document')

    adapter.set_preloaded_document(document)
    expect(adapter.preloaded_document).to be(document)

    adapter.clear_preloaded_document
    expect(adapter.preloaded_document).to be_nil
  end

  it 'stores and clears the background worker' do
    worker = instance_double('BackgroundWorker')

    adapter.set_background_worker(worker)
    expect(adapter.background_worker).to be(worker)

    adapter.clear_background_worker
    expect(adapter.background_worker).to be_nil
  end
end
