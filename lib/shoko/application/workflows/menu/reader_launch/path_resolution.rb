# frozen_string_literal: true

require_relative 'contracts'

module Shoko
  module Application
    module Workflows
      module Menu
        module ReaderLaunch
          # Resolves and validates reader/menu file paths.
          class PathResolution
            include Contracts::PathResolution

            Dependencies = Data.define(:cache_pointer_resolver, :document_path_resolver, :file_probe, :logger) do
              def validate!
                raise ArgumentError, 'cache_pointer_resolver is required' if cache_pointer_resolver.nil?
                raise ArgumentError, 'document_path_resolver is required' if document_path_resolver.nil?
                raise ArgumentError, 'file_probe is required' if file_probe.nil?

                self
              end
            end

            def initialize(deps:)
              dependencies = deps.validate!
              @cache_pointer_resolver = dependencies.cache_pointer_resolver
              @document_path_resolver = dependencies.document_path_resolver
              @file_probe = dependencies.file_probe
              @logger = dependencies.logger
            end

            def canonical_path(path)
              @document_path_resolver.canonical_reader_path(path) || path
            end

            def canonical_recent_path(path)
              @document_path_resolver.resolve_source_path(path)
            end

            def document_matches?(document, target_path)
              @document_path_resolver.document_matches_path?(document, target_path)
            end

            def file_exists?(path)
              @file_probe.exist?(path)
            end

            def file_regular?(path)
              @file_probe.file?(path)
            end

            def cache_pointer?(path)
              @cache_pointer_resolver.cache_pointer?(path)
            end

            def cache_payload(path, strict:)
              @cache_pointer_resolver.read_cache(path, strict: strict)
            end

            def valid_cache_path?(path)
              return false unless path && file_regular?(path)
              return false unless cache_pointer?(path)

              !!cache_payload(path, strict: true)
            # resilient-boundary
            rescue StandardError => e
              @logger&.debug('menu.path_resolution.valid_cache_path_failed',
                             path: path, error: e.class.name, message: e.message)
              false
            end
          end
        end
      end
    end
  end
end
