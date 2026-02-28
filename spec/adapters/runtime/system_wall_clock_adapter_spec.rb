# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Runtime::SystemWallClockAdapter do
  it 'returns a UTC Time instance' do
    value = described_class.new.utc_now
    expect(value).to be_a(Time)
    expect(value.utc?).to be(true)
  end
end
