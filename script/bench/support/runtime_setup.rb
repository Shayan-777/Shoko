# frozen_string_literal: true

module ShokoBench
  module RuntimeSetup
    module_function

    def configure!
      config = runtime_config
      Shoko::Shared::Terminal::TextMetrics.configure_runtime_config!(runtime_config: config)
      Shoko::Adapters::Output::Formatting::FormattingService::LineAssembler::Tokenizer.configure_runtime_config!(
        runtime_config: config
      )
      config
    end

    def runtime_config
      @runtime_config ||= Shoko::Adapters::Runtime::NullRuntimeConfig.instance
    end
  end
end
