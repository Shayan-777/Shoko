# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'No mixed key reads in core and normalized boundaries' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:targets) do
    [
      File.join(root, 'lib', 'shoko'),
    ].freeze
  end

  patterns = [
    /\b([a-z_]\w*)\[:([a-z_]\w*)\]\s*\|\|\s*\1\[['"]\2['"]\]/i,
    /\b([a-z_]\w*)\[['"]([a-z_]\w*)['"]\]\s*\|\|\s*\1\[:\2\]/i,
    /\b([a-z_]\w*)\[(\w+)\]\s*\|\|\s*\1\[\2\.to_s\]/i,
    /\b([a-z_]\w*)\[(\w+)\.to_s\]\s*\|\|\s*\1\[\2\]/i
  ].freeze

  def ruby_files(target)
    return [target] if File.file?(target)

    Dir[File.join(target, '**', '*.rb')]
  end

  def rel(path)
    path.delete_prefix("#{root}/")
  end

  it 'forbids mixed symbol/string fallback reads outside coercion boundaries' do
    offenders = targets.flat_map do |target|
      ruby_files(target).flat_map do |path|
        File.readlines(path).each_with_index.filter_map do |line, index|
          next if line.strip.start_with?('#')
          next unless patterns.any? { |pattern| line.match?(pattern) }

          "#{rel(path)}:#{index + 1}"
        end
      end
    end

    expect(offenders).to eq([]),
                             "Canonical payloads must be consumed without mixed-key fallback reads:\n#{offenders.join("\n")}"
  end
end
