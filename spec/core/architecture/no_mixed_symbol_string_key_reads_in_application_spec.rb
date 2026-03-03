# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'No mixed key reads in application layer' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:application_root) { File.join(root, 'lib', 'shoko', 'application') }

  PATTERNS = [
    /\b([a-z_]\w*)\[:([a-z_]\w*)\]\s*\|\|\s*\1\[['"]\2['"]\]/i,
    /\b([a-z_]\w*)\[['"]([a-z_]\w*)['"]\]\s*\|\|\s*\1\[:\2\]/i
  ].freeze

  def rel(path)
    path.delete_prefix("#{root}/")
  end

  it "forbids `x[:k] || x['k']` dual-key fallback reads" do
    offenders = []
    Dir[File.join(application_root, '**', '*.rb')].each do |path|
      File.readlines(path).each_with_index do |line, index|
        next if line.strip.start_with?('#')
        next unless PATTERNS.any? { |pattern| line.match?(pattern) }

        offenders << "#{rel(path)}:#{index + 1}"
      end
    end

    expect(offenders).to eq([]),
                         "Application layer must consume typed payloads and avoid symbol/string dual-key reads:\n#{offenders.join("\n")}"
  end
end
