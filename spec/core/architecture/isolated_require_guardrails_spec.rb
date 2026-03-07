# frozen_string_literal: true

require 'json'
require 'open3'
require 'spec_helper'

RSpec.describe 'Isolated require guardrails' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:script) { File.join(root, 'script', 'architecture', 'isolated_require_report.rb') }

  it 'requires every runtime file in isolation without relying on manifest order' do
    stdout, stderr, status = Open3.capture3('ruby', script)
    expect(status.success?).to be(true), stderr

    failures = JSON.parse(stdout)
    formatted = failures.map do |failure|
      header = failure.fetch('path')
      details = failure.fetch('stderr').to_s.lines.first(3).join
      "#{header}\n#{details}"
    end
    message = "Runtime files must declare their own dependencies:\n#{formatted.join("\n---\n")}"

    expect(formatted).to eq([]), message
  end
end
