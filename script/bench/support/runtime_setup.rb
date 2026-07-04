# frozen_string_literal: true

require_relative '../../../lib/shoko/adapters/output/terminal/null_runtime_config'
require_relative '../../../lib/shoko/shared/terminal/text_metrics'
require_relative '../../../lib/shoko/adapters/output/formatting/formatting_service'

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
      @runtime_config ||= Shoko::Adapters::Output::Terminal::NullRuntimeConfig.instance
    end
  end
end
