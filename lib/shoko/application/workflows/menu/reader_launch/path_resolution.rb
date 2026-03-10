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

            Dependencies = Data.define(:cache_pointer_resolver, :reader_document_locator, :file_probe, :logger) do
              def validate!
                raise ArgumentError, 'cache_pointer_resolver is required' if cache_pointer_resolver.nil?
                raise ArgumentError, 'reader_document_locator is required' if reader_document_locator.nil?
                raise ArgumentError, 'file_probe is required' if file_probe.nil?

                self
              end
            end

            def initialize(deps:)
              dependencies = deps.validate!
              @cache_pointer_resolver = dependencies.cache_pointer_resolver
              @reader_document_locator = dependencies.reader_document_locator
              @file_probe = dependencies.file_probe
              @logger = dependencies.logger
            end

            def canonical_path(path)
              @reader_document_locator.canonical_reader_path(path) || path
            end

            def canonical_recent_path(path)
              @reader_document_locator.resolve_source_path(path)
            end

            def document_matches?(document, target_path)
              @reader_document_locator.document_matches_path?(document, target_path)
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
            rescue Shoko::Error => e
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
