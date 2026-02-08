# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Runtime::REXMLSecurityLimitsAdapter do
  it 'applies entity expansion limits from runtime config' do
    config = instance_double(
      'RuntimeConfig',
      rexml_entity_expansion_limit: 4321,
      rexml_entity_expansion_text_limit: 54_321
    )
    adapter = described_class.new(runtime_config: config)

    prev_limit = REXML::Security.entity_expansion_limit if REXML::Security.respond_to?(:entity_expansion_limit)
    prev_text_limit =
      if REXML::Security.respond_to?(:entity_expansion_text_limit)
        REXML::Security.entity_expansion_text_limit
      end
    prev_doc_text_limit =
      if REXML::Document.respond_to?(:entity_expansion_text_limit)
        REXML::Document.entity_expansion_text_limit
      end

    adapter.apply!

    expect(REXML::Security.entity_expansion_limit).to eq(4321) if REXML::Security.respond_to?(:entity_expansion_limit)
    if REXML::Security.respond_to?(:entity_expansion_text_limit)
      expect(REXML::Security.entity_expansion_text_limit).to eq(54_321)
    end
    if REXML::Document.respond_to?(:entity_expansion_text_limit)
      expect(REXML::Document.entity_expansion_text_limit).to eq(54_321)
    end
  ensure
    if REXML::Security.respond_to?(:entity_expansion_limit=) && !prev_limit.nil?
      REXML::Security.entity_expansion_limit = prev_limit
    end
    if REXML::Security.respond_to?(:entity_expansion_text_limit=) && !prev_text_limit.nil?
      REXML::Security.entity_expansion_text_limit = prev_text_limit
    end
    if REXML::Document.respond_to?(:entity_expansion_text_limit=) && !prev_doc_text_limit.nil?
      REXML::Document.entity_expansion_text_limit = prev_doc_text_limit
    end
  end
end
