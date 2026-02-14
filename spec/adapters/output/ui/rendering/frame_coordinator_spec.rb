# frozen_string_literal: true

require 'spec_helper'
require 'shoko/test_support/terminal_double'

RSpec.describe Shoko::Adapters::Output::Ui::Rendering::FrameCoordinator do
  let(:terminal) { Shoko::TestSupport::TerminalDouble }

  class DummyStateWriter
    def update_terminal_size(*); end
  end

  class FakeTerminalService
    def initialize(terminal)
      @terminal = terminal
    end

    def size
      [24, 80]
    end

    def start_frame(width:, height:)
      @terminal.start_frame(width: width, height: height)
    end

    def end_frame
      @terminal.end_frame
    end

    def create_surface
      Shoko::Adapters::Output::Ui::Components::Surface.new(@terminal)
    end
  end

  it 'renders loading overlay without raising' do
    terminal.reset!
    terminal_service = FakeTerminalService.new(terminal)
    ui_state_reader = instance_double('UIStateReader', loading_progress: 0.5, loading_message: 'Loading')
    coordinator = described_class.new(
      terminal_service: terminal_service,
      state_writer: DummyStateWriter.new,
      ui_state_reader: ui_state_reader
    )
    expect { coordinator.render_loading_overlay }.not_to raise_error
    expect(terminal.writes).not_to be_empty
  end
end
