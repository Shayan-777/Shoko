# frozen_string_literal: true

require 'shoko/shared/thread_local_scope'
require_relative '../../errors'

module Shoko
  module Shared
    module Terminal
      module TextMetrics
        # Owns the text-metrics runtime state: the configured runtime config
        # (process-wide, thread-overridable) and the per-thread feature
        # toggles for the ASCII fast path and the two caches.
        class RuntimeControls
          RUNTIME_CONFIG_KEY = :shoko_text_metrics_runtime_config
          ASCII_FAST_PATH_ENABLED_KEY = :shoko_text_metrics_ascii_fast_path_enabled
          VISIBLE_LENGTH_CACHE_ENABLED_KEY = :shoko_visible_length_cache_enabled
          WRAP_PLAIN_TEXT_CACHE_ENABLED_KEY = :shoko_wrap_plain_text_cache_enabled

          def with_runtime_config(config:, &)
            Shoko::Shared::ThreadLocalScope.with(key: RUNTIME_CONFIG_KEY, value: config, &)
          end

          def configure_runtime_config!(runtime_config:)
            @configured_runtime_config = runtime_config
          end

          def with_ascii_fast_path(enabled:, &)
            with_thread_toggle(ASCII_FAST_PATH_ENABLED_KEY, enabled, &)
          end

          def with_visible_length_cache(enabled:, &)
            with_thread_toggle(VISIBLE_LENGTH_CACHE_ENABLED_KEY, enabled, &)
          end

          def with_wrap_plain_text_cache(enabled:, &)
            with_thread_toggle(WRAP_PLAIN_TEXT_CACHE_ENABLED_KEY, enabled, &)
          end

          def visible_length_cache_enabled?
            override = Thread.current[VISIBLE_LENGTH_CACHE_ENABLED_KEY]
            return override unless override.nil?

            !runtime_config.text_metrics_cache_disabled?
          end

          def ascii_fast_path_enabled?
            override = Thread.current[ASCII_FAST_PATH_ENABLED_KEY]
            return override unless override.nil?

            !runtime_config.text_metrics_ascii_fast_path_disabled?
          end

          def wrap_plain_text_cache_enabled?
            override = Thread.current[WRAP_PLAIN_TEXT_CACHE_ENABLED_KEY]
            return override unless override.nil?

            !runtime_config.wrap_plain_text_cache_disabled?
          end

          private

          def with_thread_toggle(key, enabled)
            previous = Thread.current[key]
            Thread.current[key] = enabled ? true : false
            yield
          ensure
            Thread.current[key] = previous
          end

          def runtime_config
            config = Thread.current[RUNTIME_CONFIG_KEY]
            config ||= @configured_runtime_config
            return config if config

            raise Shoko::ConfigurationError, 'TextMetrics runtime_config is not configured'
          end
        end
      end
    end
  end
end
