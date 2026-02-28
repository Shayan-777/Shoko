# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::UseCases::Commands::BookmarkCommandFactory do
  it 'executes add bookmark when bookmark_service is present' do
    bookmark_service = instance_double('BookmarkService', add_bookmark: nil)
    context_class = Class.new do
      include Shoko::Core::Ports::Inbound::ReaderBookmarkCommandContext

      attr_reader :bookmark_service, :logger

      def initialize(bookmark_service, logger)
        @bookmark_service = bookmark_service
        @logger = logger
      end
    end
    context = context_class.new(bookmark_service, nil)

    result = described_class.add_bookmark.execute(context, key: 'b', triggered_by: :input)

    expect(result).to eq(:handled)
    expect(bookmark_service).to have_received(:add_bookmark).with(nil)
  end
end
