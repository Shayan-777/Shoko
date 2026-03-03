# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'No legacy factory keys in runtime wiring' do
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

  it 'forbids legacy document/background factory key usage in runtime source' do
    files = Dir[File.join(lib_root, '**', '*.rb')]
    pattern = /document_service_factory|background_worker_factory/
    offenders = files.select { |path| non_comment_content(path).match?(pattern) }

    expect(offenders).to eq([]),
                         "Legacy factory keys are not allowed:\n#{offenders.map { |path| rel(path) }.join("\n")}" # rubocop:disable Layout/LineLength
  end
end
