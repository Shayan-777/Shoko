# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Zip::SizeLimits do
  it 'raises when entry sizes exceed limits' do
    limits = described_class.new(
      max_entry_uncompressed: 5,
      max_entry_compressed: 5,
      max_total_uncompressed: 10
    )
    entry = Shoko::Zip::Entry.new(
      name: 'test',
      compressed_size: 10,
      uncompressed_size: 10,
      compression_method: 0,
      gp_flags: 0,
      local_header_offset: 0
    )

    expect { limits.enforce_entry_limits(entry, requested_name: 'test') }.to raise_error(Shoko::Zip::Error)
  end
end
