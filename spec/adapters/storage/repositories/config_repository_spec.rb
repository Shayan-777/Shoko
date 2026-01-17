# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Storage::Repositories::ConfigRepository do
  let(:state_store) { Shoko::Application::Infrastructure::StateStore.new }
  let(:dependencies) do
    FakeContainer.new(global_state: state_store, logger: instance_double('Logger', error: nil))
  end

  subject(:repo) { described_class.new(dependencies) }

  it 'includes dictionary defaults in all_config' do
    config = repo.all_config

    expect(config).to include(
      dictionary_source_lang: 'auto',
      dictionary_target_lang: 'en',
      dictionary_path: nil,
      dictionary_backend: nil
    )
  end
end
