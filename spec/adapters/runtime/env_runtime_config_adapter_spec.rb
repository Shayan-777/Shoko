# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Runtime::EnvRuntimeConfigAdapter do
  it 'parses typed runtime config values from env-like input' do
    env = {
      'SHOKO_SKIP_PROGRESS_OVERLAY' => '1',
      'SHOKO_DICTIONARY' => 'SQLite',
      'SHOKO_REXML_ENTITY_LIMIT' => '123',
      'SHOKO_REXML_TEXT_LIMIT' => '456',
    }

    config = described_class.new(env: env)

    expect(config.skip_progress_overlay?).to be(true)
    expect(config.dictionary_backend_override).to eq('sqlite')
    expect(config.rexml_entity_expansion_limit).to eq(123)
    expect(config.rexml_entity_expansion_text_limit).to eq(456)
  end

  it 'falls back to defaults for invalid values' do
    env = {
      'SHOKO_SKIP_PROGRESS_OVERLAY' => '0',
      'SHOKO_REXML_ENTITY_LIMIT' => '-1',
      'SHOKO_REXML_TEXT_LIMIT' => 'abc',
    }

    config = described_class.new(env: env)

    expect(config.skip_progress_overlay?).to be(false)
    expect(config.dictionary_backend_override).to be_nil
    expect(config.rexml_entity_expansion_limit).to eq(
      Shoko::Adapters::Runtime::EnvRuntimeConfigAdapter::DEFAULT_REXML_ENTITY_EXPANSION_LIMIT
    )
    expect(config.rexml_entity_expansion_text_limit).to eq(
      Shoko::Adapters::Runtime::EnvRuntimeConfigAdapter::DEFAULT_REXML_ENTITY_EXPANSION_TEXT_LIMIT
    )
  end
end
