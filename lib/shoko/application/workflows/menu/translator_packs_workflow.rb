# frozen_string_literal: true

require_relative 'progress_throttle'
require 'shoko/application/ports/outbound/menu_session_store'
require 'shoko/application/ports/outbound/menu_transient_store'
require 'shoko/core/models/translator_pack_entry'
require 'shoko/core/services/version_order'
require_relative 'menu_state_persistence'
require_relative '../../services/async_result_relay'

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
                         async_relay: nil, logger: nil)
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
            @async_relay = async_relay || Shoko::Application::Services::AsyncResultRelay.new(logger: logger)
            @remote_by_pair = {}
            @catalog_generation = 0
          end

          def fetch_pack_catalog
            request_id = next_catalog_request_id
            update_packs_state(catalog_started_payload)
            return if @async_relay.submit { perform_catalog_fetch(request_id) }

            update_packs_state(translator_packs_status: :error,
                               translator_packs_message: 'Catalog worker is unavailable.',
                               translator_packs_progress: 0.0)
          end

          def perform_catalog_fetch(request_id)
            installed_only = installed_pack_entries
            publish_installed_pack_entries(installed_only, request_id)
            publish_remote_pack_entries(@model_catalog_service.list_remote, request_id)
          # resilient-boundary
          rescue StandardError => e
            handle_catalog_error(e, request_id)
          end
          private :perform_catalog_fetch

          def installed_pack_entries
            @model_store.installed_packs.map do |pack|
              Shoko::Core::Models::TranslatorPackEntry.from_h(
                from: pack.from, to: pack.to, version: pack.version,
                installed_version: pack.version, size: 0, installed: true,
                update_available: false
              ).to_h
            end
          end

          def publish_installed_pack_entries(entries, request_id)
            return if entries.empty?

            @async_relay.enqueue do
              next unless current_catalog_request?(request_id)

              update_packs_state(translator_packs_results: entries,
                                 translator_packs_message: 'Checking for pack updates...')
            end
          end

          def publish_remote_pack_entries(remote, request_id)
            results = merge_installation(remote)
            remote_by_pair = remote.to_h { |pack| ["#{pack.from}-#{pack.to}", pack] }
            @async_relay.enqueue do
              next unless current_catalog_request?(request_id)

              @remote_by_pair = remote_by_pair
              update_packs_state(catalog_result_payload(results))
            end
          end
          private :installed_pack_entries, :publish_installed_pack_entries, :publish_remote_pack_entries

          def download_pack(entry)
            return unless entry

            pack = coerce_pack_entry(entry)
            update_packs_state(operation_started_payload(pack))
            submitted = @async_relay.submit do
              pack.installed && !pack.update_available ? remove_pack(pack) : install_pack(pack)
            end
            return if submitted

            report_pack_worker_unavailable
          rescue Shoko::Error, ArgumentError => e
            raise if e.is_a?(Shoko::FatalExternalInputError)

            log_resilient('download_pack', e, pack: pack_label(pack))
            update_packs_state(translator_packs_status: :error,
                               translator_packs_message: "Download failed: #{e.message}",
                               translator_packs_progress: 0.0)
          end

          def install_pack(pack)
            label = pack_label(pack)
            perform_download(pack, label)
            @async_relay.enqueue do
              update_packs_state(translator_packs_status: :done,
                                 translator_packs_message: "Installed #{label}",
                                 translator_packs_progress: 0.0)
              mark_pack_installed(pack, installed: true)
            end
          # resilient-boundary
          rescue StandardError => e
            handle_download_error(e, pack)
          end

          def remove_pack(pack)
            @model_store.remove(pack.from, pack.to)
            @async_relay.enqueue do
              update_packs_state(translator_packs_status: :done,
                                 translator_packs_message: "Removed #{pack_label(pack)}",
                                 translator_packs_progress: 0.0)
              mark_pack_installed(pack, installed: false)
            end
          # resilient-boundary
          rescue StandardError => e
            handle_download_error(e, pack)
          end

          private

          def update_packs_state(payload)
            persist_menu_payload(payload)
          end

          def report_pack_worker_unavailable
            update_packs_state(translator_packs_status: :error,
                               translator_packs_message: 'Language-pack worker is unavailable.',
                               translator_packs_progress: 0.0)
          end

          def merge_installation(remote_packs)
            installed = installed_pack_index
            remote_results = Array(remote_packs).map { |remote| remote_entry(remote, installed) }
            merge_local_only_entries(remote_results, installed)
              .sort_by { |entry| [entry[:from], entry[:to]] }
          end

          def installed_pack_index
            @model_store.installed_packs.to_h { |pack| ["#{pack.from}-#{pack.to}", pack] }
          end

          def merge_local_only_entries(remote_results, installed)
            remote_keys = remote_results.to_h { |entry| ["#{entry[:from]}-#{entry[:to]}", true] }
            local_only = installed.filter_map { |key, pack| local_only_entry(pack) unless remote_keys[key] }
            remote_results + local_only
          end

          def remote_entry(remote, installed)
            local = installed["#{remote.from}-#{remote.to}"]
            Shoko::Core::Models::TranslatorPackEntry.from_h(
              from: remote.from,
              to: remote.to,
              version: remote.version,
              size: remote.total_size,
              installed: !local.nil?,
              installed_version: local&.version,
              update_available: local &&
                Shoko::Core::Services::VersionOrder.newer?(remote.version, local.version)
            ).to_h
          end

          def local_only_entry(pack)
            Shoko::Core::Models::TranslatorPackEntry.from_h(
              from: pack.from, to: pack.to, version: pack.version, size: 0,
              installed: true, installed_version: pack.version, update_available: false
            ).to_h
          end

          def perform_download(pack, label)
            remote = find_remote_pack(pack)
            last_progress = nil
            @model_catalog_service.download(remote, @model_store) do |done, total|
              progress = total.to_i.positive? ? done.to_f / total : 0.0
              next unless ProgressThrottle.publish?(progress, last_progress)

              @async_relay.enqueue do
                update_packs_state(download_progress_payload(label, progress, total))
              end
              last_progress = progress
            end
          end

          # Downloads need the attachment URLs, which the trimmed state entry
          # does not carry; resolve the pack against the live catalog.
          def find_remote_pack(pack)
            remote = @remote_by_pair[pack.pair_key]
            raise Shoko::Error, "Pack #{pack_label(pack)} is no longer in the catalog" unless remote

            remote
          end

          def mark_pack_installed(pack, installed:)
            results = Array(current_menu.translator_packs_results).map { |entry| coerce_pack_entry(entry) }
            return if results.empty?

            updated = results.map do |item|
              next item unless item.pair_key == pack.pair_key

              pack_with_installation(item, installed:)
            end
            update_packs_state(translator_packs_results: updated.map(&:to_h))
          end

          def catalog_started_payload
            {
              translator_packs_status: :loading,
              translator_packs_message: 'Loading language pack list...',
              translator_packs_progress: 0.0,
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

          def operation_started_payload(pack)
            verb = if pack.installed && pack.update_available
                     'Updating'
                   elsif pack.installed
                     'Removing'
                   else
                     'Downloading'
                   end
            {
              translator_packs_status: :downloading,
              translator_packs_message: "#{verb} #{pack_label(pack)}...",
              translator_packs_progress: 0.0,
            }
          end

          def handle_catalog_error(error, request_id)
            raise error if error.is_a?(Shoko::FatalExternalInputError)

            @async_relay.enqueue do
              next unless current_catalog_request?(request_id)

              log_resilient('fetch_pack_catalog', error)
              update_packs_state(translator_packs_status: :error,
                                 translator_packs_message: "Catalog failed: #{error.message}",
                                 translator_packs_progress: 0.0)
            end
          end

          def handle_download_error(error, pack)
            raise error if error.is_a?(Shoko::FatalExternalInputError)

            @async_relay.enqueue do
              log_resilient('download_pack', error, pack: pack_label(pack))
              update_packs_state(translator_packs_status: :error,
                                 translator_packs_message: "Download failed: #{error.message}",
                                 translator_packs_progress: 0.0)
            end
          end

          def pack_with_installation(pack, installed:)
            Shoko::Core::Models::TranslatorPackEntry.from_h(
              pack.to_h.merge(
                installed: installed,
                update_available: false,
                installed_version: installed ? pack.version : ''
              )
            )
          end

          def next_catalog_request_id
            @catalog_generation += 1
          end

          def current_catalog_request?(request_id)
            request_id == @catalog_generation
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
