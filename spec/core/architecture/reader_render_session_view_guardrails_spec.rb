# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Reader render session-view guardrails' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:files) do
    %w[
      lib/shoko/bootstrap/container_factory.rb
      lib/shoko/bootstrap/container_factory/domain_application_registration/domain_services.rb
      lib/shoko/bootstrap/container_factory/domain_application_registration/output_services.rb
      lib/shoko/bootstrap/container_factory/controller_composition/reader_builder.rb
      lib/shoko/bootstrap/container_factory/controller_composition/menu_builder.rb
    ].map { |path| File.join(root, path) }
  end

  def non_comment_content(path)
    File.readlines(path).reject { |line| line.strip.start_with?('#') }.join
  end

  it 'keeps the reader/menu bootstrap render slice off legacy read-port resolutions' do
    forbidden_patterns = [
      /resolve\(:config_reader\)/,
      /resolve\(:reader_state_reader\)/,
      /resolve\(:reader_navigation_reader\)/,
      /resolve\(:ui_state_reader\)/,
      /resolve\(:sidebar_state_reader\)/,
      /resolve\(:menu_state_reader\)/
    ]

    offenders = files.filter_map do |path|
      content = non_comment_content(path)
      next unless forbidden_patterns.any? { |pattern| content.match?(pattern) }

      path.delete_prefix("#{root}/")
    end

    expect(offenders).to eq([]),
      "Reader render/output bootstrap slice still resolves legacy read ports:\n#{offenders.join("\n")}"
  end
end
