# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'No Proc type fallback checks in runtime code' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:lib_root) { File.join(root, 'lib', 'shoko') }

  def non_comment_content(path)
    File.readlines(path).reject { |line| line.strip.start_with?('#') }.join
  rescue StandardError
    ''
  end

  def rel(path)
    path.delete_prefix("#{root}/")
  end

  it 'forbids is_a?(Proc) fallback probing in runtime source' do
    files = Dir[File.join(lib_root, '**', '*.rb')]
    pattern = /\bis_a\?\(Proc\)/
    offenders = files.select { |path| non_comment_content(path).match?(pattern) }

    expect(offenders).to eq([]),
                         "Proc type fallback probing is not allowed:\n#{offenders.map { |path| rel(path) }.join("\n")}" # rubocop:disable Layout/LineLength
  end
end
