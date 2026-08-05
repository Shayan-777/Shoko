# frozen_string_literal: true

require 'spec_helper'
require 'yaml'

RSpec.describe 'Runtime dependency policy' do
  it 'requires each runtime gem to have an explicit architectural record' do
    root = File.expand_path('../..', __dir__)
    gemspec = Gem::Specification.load(File.join(root, 'Shoko.gemspec'))
    raise 'Could not load Shoko.gemspec' unless gemspec

    policy = YAML.safe_load_file(File.join(root, 'docs/architecture/runtime-dependencies.yml'))
    records = policy.fetch('dependencies')
    declared = gemspec.dependencies.select(&:runtime?).to_h { |dependency| [dependency.name, dependency] }

    expect(records.keys.sort).to eq(declared.keys.sort)
    records.each do |name, record|
      expect(record.fetch('rationale').to_s.strip).not_to be_empty, "#{name} has no rationale"
      expect(record.fetch('owner').to_s.strip).not_to be_empty, "#{name} has no owner"
      expect(record.fetch('reviewed_on').to_s).to match(/\A\d{4}-\d{2}-\d{2}\z/)
      expect(record.fetch('requirement').to_s).to eq(declared.fetch(name).requirement.to_s)
    end
  end
end
