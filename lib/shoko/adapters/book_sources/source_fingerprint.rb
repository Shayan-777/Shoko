# frozen_string_literal: true

# Backward-compat alias: SourceFingerprint moved to Shoko::Shared::SourceFingerprint
require_relative '../../shared/source_fingerprint'

module Shoko
  module Adapters::BookSources
    SourceFingerprint = Shoko::Shared::SourceFingerprint
  end
end
