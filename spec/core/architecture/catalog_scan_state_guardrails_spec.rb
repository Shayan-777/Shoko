# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Catalog scan-state guardrails' do
  let(:root) { File.expand_path('../../..', __dir__) }

  def relative(path)
    path.delete_prefix("#{root}/")
  end

  it 'forbids direct scan_status/scan_message mutation outside catalog service' do
    files = Dir[File.join(root, 'lib', 'shoko', '**', '*.rb')]
    files -= [
      File.join(root, 'lib', 'shoko', 'application', 'use_cases', 'catalog_service.rb'),
      File.join(root, 'lib', 'shoko', 'adapters', 'book_sources', 'library_scanner.rb')
    ]
    # Match assignment (=) but not comparison (==).
    pattern = /\bscan_(?:status|message)\s*=(?!=)/

    offenders = files.filter_map do |path|
      next unless File.read(path).match?(pattern)

      relative(path)
    end

    expect(offenders).to be_empty,
                         "Scan-state mutation must stay behind CatalogService API:\n#{offenders.sort.join("\n")}"
  end
end
