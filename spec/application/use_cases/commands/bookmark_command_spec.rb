# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::UseCases::Commands::BookmarkCommandFactory do
  it 'executes add bookmark when bookmark_service is present' do
    bookmark_service = instance_double('BookmarkService', add_bookmark: nil)
    context = Struct.new(:bookmark_service, :logger).new(bookmark_service, nil)

    result = described_class.add_bookmark.execute(context, key: 'b', triggered_by: :input)

    expect(result).to eq(:handled)
    expect(bookmark_service).to have_received(:add_bookmark).with(nil)
  end
end
