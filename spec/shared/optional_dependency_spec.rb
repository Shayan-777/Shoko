# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Shared::OptionalDependency do
  let(:missing_gem) { 'shoko_missing_optional_gem_for_spec' }

  before do
    described_class.instance_variable_set(:@spec_cache, nil)
  end

  describe '.find_gemspec' do
    it 'returns nil for a gem that is not installed' do
      expect(described_class.send(:find_gemspec, missing_gem)).to be_nil
    end
  end

  describe '.require_gem!' do
    it 'raises DependencyUnavailableError for a gem that is not installed' do
      expect do
        described_class.require_gem!(missing_gem)
      end.to raise_error(Shoko::DependencyUnavailableError, /optional gem '#{missing_gem}'/)
    end
  end
end
