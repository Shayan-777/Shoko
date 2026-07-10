# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Services::Pagination::Internal::PaginationWorkflow do
  it 'passes text metrics to absolute pagination fallback builder' do
    metrics_calculator = instance_double(Shoko::Application::Services::Pagination::Internal::LayoutMetricsCalculator)
    display_capabilities = instance_double(Shoko::Application::Ports::Outbound::DisplayCapabilities)
    instrumentation = instance_double(Shoko::Application::Ports::Outbound::Instrumentation)
    text_metrics = instance_double(Shoko::Application::Ports::Outbound::TextMetrics)
    config_reader = instance_double(Shoko::Application::Ports::Outbound::State::ConfigSnapshot, view_mode: :single, line_spacing: :normal)
    doc = instance_double(Shoko::Application::Models::ReaderDocument)

    allow(metrics_calculator).to receive(:layout).and_return([80, 20])
    allow(metrics_calculator).to receive(:lines_per_page_for).and_return(10)
    allow(instrumentation).to receive(:annotate)
    allow(display_capabilities).to receive(:kitty_images_enabled?).and_return(false)

    workflow = described_class.new(
      metrics_calculator: metrics_calculator,
      display_capabilities: display_capabilities,
      instrumentation: instrumentation,
      text_metrics: text_metrics,
      config_reader: config_reader
    )

    expect(Shoko::Core::Services::Pagination::Internal::AbsolutePageMapBuilder).to receive(:build).with(
      doc,
      80,
      10,
      nil,
      text_metrics: text_metrics
    ).and_return([2])

    expect(workflow.build_absolute(doc: doc, width: 120, height: 40)).to eq([2])
  end
end
