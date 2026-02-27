# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Dependency constructor guardrails' do
  let(:root) { File.expand_path('../../..', __dir__) }

  it 'forbids initialize(**deps) on critical controller/workflow classes' do
    files = [
      File.join(root, 'lib', 'shoko', 'application', 'workflows', 'menu', 'reader_launch_service.rb'),
      File.join(root, 'lib', 'shoko', 'adapters', 'input', 'controllers', 'state_controller.rb'),
      File.join(root, 'lib', 'shoko', 'adapters', 'input', 'controllers', 'sidebar_controller.rb'),
      File.join(root, 'lib', 'shoko', 'adapters', 'input', 'controllers', 'dictionary_controller.rb')
    ]
    offenders = files.filter_map do |path|
      content = File.read(path)
      next unless content.match?(/def initialize\s*\([^)]*\*\*deps/)

      path.delete_prefix("#{root}/")
    end

    expect(offenders).to be_empty,
                         "Critical classes must use typed dependency objects instead of **deps:\n#{offenders.join("\n")}"
  end
end
