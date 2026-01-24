# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Core adapter boundaries' do
  it 'avoids adapter constants in core sources' do
    root = File.expand_path('../../../lib/shoko/core', __dir__)
    files = Dir[File.join(root, '**', '*.rb')]
    offenders = files.select do |path|
      File.read(path).include?('Shoko::Adapters::')
    end

    expect(offenders).to be_empty, "Core files reference adapters:\n#{offenders.join("\n")}"
  end
end
