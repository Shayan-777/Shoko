# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::ReaderInputController do
  describe "read-mode quit binding" do
    let(:reader_state_reader) { instance_double('ReaderStateReader') }
    let(:state_writer) { instance_double('StateWriter') }
    let(:command_port) { Shoko::Adapters::Input::CommandPortAdapter.new }
    let(:state_controller) { instance_double('StateController', quit_to_menu: nil) }
    let(:context) do
      Struct.new(:command_port, :state_controller).new(command_port, state_controller)
    end

    it "dispatches 'q' to quit_to_menu" do
      controller = described_class.new(
        reader_state_reader: reader_state_reader,
        state_writer: state_writer,
        command_port: command_port
      )
      controller.setup_input_dispatcher(context)

      controller.handle_key('q')

      expect(state_controller).to have_received(:quit_to_menu)
    end
  end
end
