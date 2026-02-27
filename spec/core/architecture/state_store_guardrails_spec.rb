# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'State store guardrails' do
  let(:root) { File.expand_path('../../..', __dir__) }

  it 'forbids direct filesystem probes in runtime state stores' do
    files = [
      File.join(root, 'lib', 'shoko', 'adapters', 'runtime', 'session_state', 'state_store.rb'),
      File.join(root, 'lib', 'shoko', 'adapters', 'runtime', 'session_state', 'observer_state_store.rb')
    ]
    offenders = files.filter_map do |path|
      content = File.read(path)
      next unless content.include?('File.exist?')

      path.delete_prefix("#{root}/")
    end

    expect(offenders).to be_empty,
                         "State stores must use config storage port instead of File.exist?:\n#{offenders.join("\n")}"
  end

  it 'requires runtime state stores to rely on config_storage.file_exist?' do
    files = [
      File.join(root, 'lib', 'shoko', 'adapters', 'runtime', 'session_state', 'state_store.rb'),
      File.join(root, 'lib', 'shoko', 'adapters', 'runtime', 'session_state', 'observer_state_store.rb')
    ]
    missing = files.filter_map do |path|
      content = File.read(path)
      next if content.include?('file_exist?')

      path.delete_prefix("#{root}/")
    end

    expect(missing).to be_empty,
                       "State stores must delegate existence checks to config storage port:\n#{missing.join("\n")}"
  end
end
