# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Pagination compatibility shims' do
  describe Shoko::Core::Services::Pagination::PaginationOrchestrator do
    it 'logs a deprecation warning when instantiated' do
      logger = instance_double('Logger', warn: nil)

      described_class.new(
        terminal_service: instance_double('TerminalService', size: [24, 80]),
        display_capabilities: instance_double('DisplayCapabilities'),
        instrumentation: instance_double('Instrumentation'),
        pagination_cache: nil,
        frame_coordinator: nil,
        logger: logger
      )

      expect(logger).to have_received(:warn).with(include('DEPRECATION'))
    end
  end

  describe Shoko::Core::Services::Pagination::PaginationCoordinator do
    it 'logs a deprecation warning when instantiated' do
      logger = instance_double('Logger', warn: nil, debug: nil)

      described_class.new(
        doc: instance_double('Document', cached?: false),
        page_calculator: instance_double('PageCalculator', total_pages: 0, reset_session!: nil),
        layout_service: instance_double('LayoutService'),
        terminal_service: instance_double('TerminalService', size: [24, 80]),
        pagination_cache: nil,
        frame_coordinator: nil,
        render_callback: nil,
        async_executor: instance_double('AsyncExecutor', submit: nil),
        display_capabilities: instance_double('DisplayCapabilities'),
        instrumentation: instance_double('Instrumentation', measure: nil),
        config_reader: instance_double('ConfigReader', page_numbering_mode: :dynamic),
        reader_state_reader: instance_double('ReaderStateReader', total_pages: 0),
        state_writer: instance_double('StateWriter'),
        notification_writer: nil,
        logger: logger
      )

      expect(logger).to have_received(:warn).with(include('DEPRECATION'))
    end
  end
end
