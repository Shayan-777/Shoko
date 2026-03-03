# frozen_string_literal: true

require_relative '../../../shared/runtime/null_runtime_config'
require_relative '../../../core/ports/outbound/runtime_config'

module Shoko
  module Adapters
    module Output
      module Terminal
        # Output-local null runtime config implementing outbound RuntimeConfig.
        class NullRuntimeConfig < Shoko::Shared::Runtime::NullRuntimeConfig
          include Shoko::Core::Ports::Outbound::RuntimeConfig

          Core::Ports::Outbound::RuntimeConfig.instance_methods(false).each do |method_name|
            define_method(method_name) do |*args, **kwargs, &block|
              self.class.superclass.instance_method(method_name).bind_call(self, *args, **kwargs, &block)
            end
          end
        end
      end
    end
  end
end
