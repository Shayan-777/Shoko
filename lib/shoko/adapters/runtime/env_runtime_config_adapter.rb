# frozen_string_literal: true

require_relative '../../core/ports/runtime_config'

module Shoko
  module Adapters
    module Runtime
      # Reads process runtime configuration from environment variables once and
      # exposes typed values through the RuntimeConfig port.
      class EnvRuntimeConfigAdapter
        include Core::Ports::RuntimeConfig

        DEFAULT_REXML_ENTITY_EXPANSION_LIMIT = 10_000
        DEFAULT_REXML_ENTITY_EXPANSION_TEXT_LIMIT = 2_000_000

        def initialize(env: ENV)
          @skip_progress_overlay = env_flag(env, 'SHOKO_SKIP_PROGRESS_OVERLAY')
          @dictionary_backend_override = env_value(env, 'SHOKO_DICTIONARY')
          @rexml_entity_expansion_limit = env_positive_integer(
            env,
            'SHOKO_REXML_ENTITY_LIMIT',
            fallback: DEFAULT_REXML_ENTITY_EXPANSION_LIMIT
          )
          @rexml_entity_expansion_text_limit = env_positive_integer(
            env,
            'SHOKO_REXML_TEXT_LIMIT',
            fallback: DEFAULT_REXML_ENTITY_EXPANSION_TEXT_LIMIT
          )
        end

        def skip_progress_overlay?
          @skip_progress_overlay
        end

        def dictionary_backend_override
          @dictionary_backend_override
        end

        def rexml_entity_expansion_limit
          @rexml_entity_expansion_limit
        end

        def rexml_entity_expansion_text_limit
          @rexml_entity_expansion_text_limit
        end

        private

        def env_flag(env, key)
          env_value(env, key) == '1'
        end

        def env_value(env, key)
          raw = fetch_env(env, key)
          value = raw.to_s.strip.downcase
          value.empty? ? nil : value
        rescue StandardError
          nil
        end

        def env_positive_integer(env, key, fallback:)
          raw = fetch_env(env, key)
          value = raw.to_s.strip
          return fallback if value.empty?

          parsed = value.to_i
          parsed.positive? ? parsed : fallback
        rescue StandardError
          fallback
        end

        def fetch_env(env, key)
          return env[key] if env.respond_to?(:[])
          return env.fetch(key, nil) if env.respond_to?(:fetch)

          nil
        end
      end
    end
  end
end
