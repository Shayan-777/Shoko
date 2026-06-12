# frozen_string_literal: true

require 'shoko/shared/runtime/null_runtime_config'
require 'shoko/application/ports/outbound/runtime_config'

module Shoko
  module Adapters
    module Output
      module Terminal
        # Output-local null runtime config implementing outbound RuntimeConfig.
        class NullRuntimeConfig < Shoko::Shared::Runtime::NullRuntimeConfig
          include Shoko::Application::Ports::Outbound::RuntimeConfig

          Application::Ports::Outbound::RuntimeConfig.instance_methods(false).each do |method_name|
            define_method(method_name) do |*args, **kwargs, &block|
              self.class.superclass.instance_method(method_name).bind_call(self, *args, **kwargs, &block)
            end
          end
        end
      end
    end
  end
end
