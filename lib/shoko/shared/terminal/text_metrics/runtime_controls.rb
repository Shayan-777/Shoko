# frozen_string_literal: true

module Shoko
  module Shared
    module Terminal
      module TextMetrics
        # Runtime-config and cache-toggle helpers for text metrics.
        module RuntimeControls
          def with_runtime_config(config:)
            previous = Thread.current[RUNTIME_CONFIG_KEY]
            Thread.current[RUNTIME_CONFIG_KEY] = config if config
            yield
          ensure
            Thread.current[RUNTIME_CONFIG_KEY] = previous
          end

          def configure_runtime_config!(runtime_config:)
            @configured_runtime_config = runtime_config
          end

          def with_ascii_fast_path(enabled:)
            previous = Thread.current[ASCII_FAST_PATH_ENABLED_KEY]
            Thread.current[ASCII_FAST_PATH_ENABLED_KEY] = enabled ? true : false
            yield
          ensure
            Thread.current[ASCII_FAST_PATH_ENABLED_KEY] = previous
          end

          def clear_visible_length_cache
            Thread.current[VISIBLE_LENGTH_CACHE_KEY] = {}
          end

          def clear_wrap_plain_text_cache
            Thread.current[WRAP_PLAIN_TEXT_CACHE_KEY] = {}
            Thread.current[WRAP_PLAIN_TEXT_CACHE_ORDER_KEY] = []
          end

          def with_visible_length_cache(enabled:)
            previous = Thread.current[VISIBLE_LENGTH_CACHE_ENABLED_KEY]
            Thread.current[VISIBLE_LENGTH_CACHE_ENABLED_KEY] = enabled ? true : false
            yield
          ensure
            Thread.current[VISIBLE_LENGTH_CACHE_ENABLED_KEY] = previous
          end

          def with_wrap_plain_text_cache(enabled:)
            previous = Thread.current[WRAP_PLAIN_TEXT_CACHE_ENABLED_KEY]
            Thread.current[WRAP_PLAIN_TEXT_CACHE_ENABLED_KEY] = enabled ? true : false
            yield
          ensure
            Thread.current[WRAP_PLAIN_TEXT_CACHE_ENABLED_KEY] = previous
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
