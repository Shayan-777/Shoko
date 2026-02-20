# frozen_string_literal: true

require_relative '../../adapters/runtime/null_runtime_config'

module Shoko
  module Shared
    module Runtime
      # Shared alias for runtime null-config fallback.
      NullRuntimeConfig = Shoko::Adapters::Runtime::NullRuntimeConfig
    end
  end
end
