# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Namespace guardrails' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:lib_root) { File.join(root, 'lib', 'shoko') }

  def relative(path)
    path.delete_prefix("#{root}/")
  end

  it 'forbids shorthand module declarations in runtime code' do
    pattern = /^\s*module [A-Z][A-Za-z0-9_]*(::[A-Z][A-Za-z0-9_]*)+/
    offenders = Dir[File.join(lib_root, '**', '*.rb')].filter_map do |path|
      next unless File.foreach(path).any? { |line| line.match?(pattern) }

      relative(path)
    end

    expect(offenders).to be_empty,
                         "Shorthand module declarations must not be used:\n#{offenders.sort.join("\n")}"
  end

  it 'forbids synthetic namespace preload files' do
    namespaces_file = File.join(lib_root, 'shared', 'namespaces.rb')

    expect(File.exist?(namespaces_file)).to eq(false),
                                           "Synthetic namespace preload file must remain removed:\n#{relative(namespaces_file)}"
  end

  it 'forbids runtime bootstrap manifest from injecting namespace preload entries' do
    bootstrap_file = File.join(lib_root, 'bootstrap', 'runtime_bootstrap.rb')
    content = File.read(bootstrap_file)

    expect(content).not_to include('shared/namespaces'),
                           'Runtime bootstrap manifest must not inject shared namespace preloads'
  end
end
