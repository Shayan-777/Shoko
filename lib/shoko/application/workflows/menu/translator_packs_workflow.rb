# frozen_string_literal: true

require_relative 'progress_throttle'
require 'shoko/application/ports/outbound/menu_session_store'
require 'shoko/application/ports/outbound/menu_transient_store'
require 'shoko/core/models/translator_pack_entry'
require_relative 'menu_state_persistence'

module Shoko
  module Application
    module Workflows
      module Menu
        # Coordinates the translator language-pack catalog: listing what the
        # model provider offers, marking what is installed, and downloading
        # or removing packs.
        class TranslatorPacksWorkflow
          include MenuStatePersistence

          def initialize(model_catalog_service:, model_store:, menu_session_store:, menu_transient_store:,
                         logger: nil)
            raise ArgumentError, 'model_catalog_service is required' if model_catalog_service.nil?
            raise ArgumentError, 'model_store is required' if model_store.nil?
            unless menu_session_store.is_a?(Shoko::Application::Ports::Outbound::MenuSessionStore)
              raise ArgumentError, 'menu_session_store must implement Application::Ports::Outbound::MenuSessionStore'
            end
            unless menu_transient_store.is_a?(Shoko::Application::Ports::Outbound::MenuTransientStore)
              raise ArgumentError, 'menu_transient_store must implement Application::Ports::Outbound::MenuTransientStore'
            end

            @model_catalog_service = model_catalog_service
            @model_store = model_store
            @menu_session_store = menu_session_store
            @menu_transient_store = menu_transient_store
            @logger = logger
          end

          def fetch_pack_catalog
            update_packs_state(catalog_started_payload)
            remote = @model_catalog_service.list_remote
            results = merge_installation(remote)
            update_packs_state(catalog_result_payload(results))
          rescue Shoko::Error => e
            raise if e.is_a?(Shoko::FatalExternalInputError)

            log_resilient('fetch_pack_catalog', e)
            update_packs_state(translator_packs_status: :error,
                               translator_packs_message: "Catalog failed: #{e.message}",
                               translator_packs_progress: 0.0)
          end

          def download_pack(entry)
            return unless entry

            pack = coerce_pack_entry(entry)
            return remove_pack(pack) if pack.installed

            install_pack(pack)
          rescue Shoko::Error => e
            raise if e.is_a?(Shoko::FatalExternalInputError)

            log_resilient('download_pack', e, pack: pack_label(pack))
            update_packs_state(translator_packs_status: :error,
                               translator_packs_message: "Download failed: #{e.message}",
                               translator_packs_progress: 0.0)
          end

          def install_pack(pack)
            label = pack_label(pack)
            update_packs_state(download_started_payload(label))
            perform_download(pack, label)
            update_packs_state(translator_packs_status: :done,
                               translator_packs_message: "Installed #{label}",
                               translator_packs_progress: 0.0)
            mark_pack_installed(pack, installed: true)
          end

          def remove_pack(pack)
            @model_store.remove(pack.from, pack.to)
            update_packs_state(translator_packs_status: :done,
                               translator_packs_message: "Removed #{pack_label(pack)}",
                               translator_packs_progress: 0.0)
            mark_pack_installed(pack, installed: false)
          end

          private

          def update_packs_state(payload)
            persist_menu_payload(payload)
          end

          def merge_installation(remote_packs)
            installed = @model_store.installed_packs.to_h { |pack| ["#{pack.from}-#{pack.to}", pack] }
            Array(remote_packs).map do |remote|
              Shoko::Core::Models::TranslatorPackEntry.from_h(
                from: remote.from,
                to: remote.to,
                version: remote.version,
                size: remote.total_size,
                installed: installed.key?("#{remote.from}-#{remote.to}")
              ).to_h
            end
          end

          def perform_download(pack, label)
            remote = find_remote_pack(pack)
            last_progress = nil
            @model_catalog_service.download(remote, @model_store) do |done, total|
              progress = total.to_i.positive? ? done.to_f / total : 0.0
              next unless ProgressThrottle.publish?(progress, last_progress)

              update_packs_state(download_progress_payload(label, progress, total))
              last_progress = progress
            end
          end

          # Downloads need the attachment URLs, which the trimmed state entry
          # does not carry; resolve the pack against the live catalog.
          def find_remote_pack(pack)
            remote = @model_catalog_service.list_remote.find do |candidate|
              candidate.from == pack.from && candidate.to == pack.to
            end
            raise Shoko::Error, "Pack #{pack_label(pack)} is no longer in the catalog" unless remote

            remote
          end

          def mark_pack_installed(pack, installed:)
            results = Array(current_menu.translator_packs_results).map { |entry| coerce_pack_entry(entry) }
            return if results.empty?

            updated = results.map do |item|
              next item unless item.pair_key == pack.pair_key

              item.with_installation(installed: installed)
            end
            update_packs_state(translator_packs_results: updated.map(&:to_h))
          end

          def catalog_started_payload
            {
              translator_packs_status: :loading,
              translator_packs_message: 'Loading language pack list...',
              translator_packs_progress: 0.0,
              translator_packs_results: [],
              translator_packs_selected: 0,
            }
          end

          def catalog_result_payload(results)
            {
              translator_packs_status: :done,
              translator_packs_message: "Found #{results.length} language packs",
              translator_packs_progress: 0.0,
              translator_packs_results: results,
              translator_packs_selected: 0,
            }
          end

          def download_started_payload(label)
            {
              translator_packs_status: :downloading,
              translator_packs_message: "Downloading #{label}...",
              translator_packs_progress: 0.0,
            }
          end

          def download_progress_payload(label, progress, total)
            percent = total.to_i.positive? ? (progress * 100).round : nil
            message = percent ? "Downloading #{label}... #{percent}%" : "Downloading #{label}..."
            { translator_packs_progress: progress, translator_packs_message: message }
          end

          def pack_label(pack)
            return 'pack' unless pack

            "#{pack.from} → #{pack.to}"
          end

          # Entries only ever come from this workflow's own state writes, so a
          # malformed one is a programming error — from_h's ArgumentError is
          # allowed to crash loudly rather than degrade into an error banner.
          def coerce_pack_entry(value)
            return value if value.is_a?(Shoko::Core::Models::TranslatorPackEntry)

            Shoko::Core::Models::TranslatorPackEntry.from_h(value)
          end

          def log_resilient(operation, error, **metadata)
            @logger&.error(
              "menu.translator_packs_workflow.#{operation}_failed",
              error: error.class.name,
              message: error.message,
              **metadata
            )
          end
        end
      end
    end
  end
end
