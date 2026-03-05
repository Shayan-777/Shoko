# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Runtime gem dependency policy' do
  it 'does not declare third-party runtime gem dependencies' do
    gemspec_path = File.expand_path('../../Shoko.gemspec', __dir__)
    spec = Gem::Specification.load(gemspec_path)
    runtime_dependencies = spec.dependencies.select(&:runtime?)
    dependency_names = runtime_dependencies.map(&:name)

    expect(runtime_dependencies).to be_empty, "Runtime dependencies found: #{dependency_names.join(', ')}"
  end
end
