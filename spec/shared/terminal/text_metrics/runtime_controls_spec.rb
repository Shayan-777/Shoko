# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Shared::Terminal::TextMetrics::RuntimeControls do
  subject(:controls) { described_class.new }

  def config(cache_disabled: false, ascii_disabled: false, wrap_disabled: false)
    cfg = Object.new
    cfg.define_singleton_method(:text_metrics_cache_disabled?) { cache_disabled }
    cfg.define_singleton_method(:text_metrics_ascii_fast_path_disabled?) { ascii_disabled }
    cfg.define_singleton_method(:wrap_plain_text_cache_disabled?) { wrap_disabled }
    cfg
  end

  it 'raises ConfigurationError when no runtime config is configured' do
    expect { controls.ascii_fast_path_enabled? }.to raise_error(Shoko::ConfigurationError, /not configured/)
  end

  it 'derives the three toggles from the configured runtime config' do
    controls.configure_runtime_config!(runtime_config: config(cache_disabled: true))

    expect(controls.visible_length_cache_enabled?).to be(false)
    expect(controls.ascii_fast_path_enabled?).to be(true)
    expect(controls.wrap_plain_text_cache_enabled?).to be(true)
  end

  it 'scopes with_runtime_config to the block and restores the previous value' do
    controls.configure_runtime_config!(runtime_config: config(ascii_disabled: true))

    controls.with_runtime_config(config: config(ascii_disabled: false)) do
      expect(controls.ascii_fast_path_enabled?).to be(true)
    end
    expect(controls.ascii_fast_path_enabled?).to be(false)
  end

  it 'lets thread-local toggles override the config inside their block only' do
    controls.configure_runtime_config!(runtime_config: config)

    controls.with_ascii_fast_path(enabled: false) do
      expect(controls.ascii_fast_path_enabled?).to be(false)
    end
    expect(controls.ascii_fast_path_enabled?).to be(true)

    controls.with_wrap_plain_text_cache(enabled: false) do
      expect(controls.wrap_plain_text_cache_enabled?).to be(false)
    end
    controls.with_visible_length_cache(enabled: false) do
      expect(controls.visible_length_cache_enabled?).to be(false)
    end
  end
end
