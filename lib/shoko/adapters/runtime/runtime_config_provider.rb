# frozen_string_literal: true

require_relative 'env_runtime_config_adapter'

module Shoko
  module Adapters
    module Runtime
      # Shared runtime config accessor for adapters that cannot receive constructor
      # injection (module-level or class-level utility paths).
      module RuntimeConfigProvider
        module_function

        def runtime_config
          @runtime_config ||= Shoko::Adapters::Runtime::EnvRuntimeConfigAdapter.new
        end
      end
    end
  end
end
