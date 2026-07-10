# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Runtime::SessionState::ReaderLaunchStateAdapter do
  subject(:adapter) { described_class.new }

  it 'stores and clears the preloaded document' do
    document = instance_double(Shoko::Application::Models::ReaderDocument)

    adapter.preloaded_document = document
    expect(adapter.preloaded_document).to be(document)

    adapter.clear_preloaded_document
    expect(adapter.preloaded_document).to be_nil
  end

  it 'stores and clears the background worker' do
    worker = instance_double(Shoko::Adapters::Storage::BackgroundWorker)

    adapter.background_worker = worker
    expect(adapter.background_worker).to be(worker)

    adapter.clear_background_worker
    expect(adapter.background_worker).to be_nil
  end
end
