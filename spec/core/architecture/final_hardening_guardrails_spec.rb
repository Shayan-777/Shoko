# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Final hardening guardrails' do
  let(:root) { File.expand_path('../../..', __dir__) }

  def read(relative_path)
    File.read(File.join(root, relative_path))
  end

  it 'keeps migration-era compatibility shims removed from migrated services' do
    expect(Shoko::Application::Services::Pagination::PageCalculatorService.instance_methods(false))
      .not_to include(:build_page_map)
    expect(Shoko::Application::Services::CoordinateService.instance_methods(false))
      .not_to include(:column_bounds_for)
    expect(Shoko::Adapters::Ui::Components::Ui::OverlayLayout.instance_methods(false))
      .not_to include(:start_col, :start_row)
  end

  it 'keeps migrated files free of stale migration wording for removed shims' do
    offenders = {
      'lib/shoko/application/services/pagination/page_calculator_service.rb' => [
        /PageManager compatibility/,
        /\bbuild_page_map\s*\(/
      ],
      'lib/shoko/application/services/coordinate_service.rb' => [
        /legacy coordinate ranges/,
        /\bcolumn_bounds_for\s*\(/
      ],
      'lib/shoko/adapters/ui/components/ui/overlay_layout.rb' => [
        /Backward-compatible accessors/,
        /\bstart_col\b/,
        /\bstart_row\b/
      ],
      'lib/shoko/adapters/runtime/session_state/event_publisher_adapter.rb' => [
        /legacy EventBus shape/
      ]
    }.flat_map do |relative_path, patterns|
      content = read(relative_path)
      patterns.filter_map do |pattern|
        "#{relative_path}: #{pattern.inspect}" if content.match?(pattern)
      end
    end

    expect(offenders).to eq([]),
                             "Migrated files still contain removed compatibility shims or stale wording:\n#{offenders.join("\n")}"
  end
end
