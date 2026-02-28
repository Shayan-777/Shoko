# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::UseCases::Commands::NavigationCommand do
  class TypedNavigationContext
    include Shoko::Core::Ports::Inbound::ReaderNavigationCommandContext

    attr_reader :navigation_service, :reader_state_reader, :logger

    def initialize(navigation_service:, reader_state_reader:, logger: nil)
      @navigation_service = navigation_service
      @reader_state_reader = reader_state_reader
      @logger = logger
    end
  end

  let(:navigation_service) do
    instance_double(
      'NavigationService',
      next_page: nil,
      prev_page: nil,
      jump_to_chapter: nil,
      go_to_start: nil,
      go_to_end: nil,
      scroll: nil
    )
  end
  let(:reader_state_reader) { instance_double('ReaderStateReader', current_chapter: 3) }

  it 'executes semantic navigation with typed context' do
    command = described_class.new(:next_page)
    context = TypedNavigationContext.new(
      navigation_service: navigation_service,
      reader_state_reader: reader_state_reader
    )

    expect(command.execute(context, key: 'j', triggered_by: :input)).to eq(:handled)
    expect(navigation_service).to have_received(:next_page).once
  end

  it 'fails deterministically for untyped context' do
    command = described_class.new(:next_page)

    expect do
      command.execute(Object.new, key: 'j')
    end.to raise_error(
      Shoko::Application::UseCases::Commands::BaseCommand::ValidationError,
      /ReaderNavigationCommandContext/
    )
  end
end
