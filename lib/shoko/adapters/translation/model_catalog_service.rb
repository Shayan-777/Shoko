# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'
require_relative '../base_adapter'
require_relative '../../shared/errors'

module Shoko
  module Adapters
    module Translation
      # Fetches the Firefox Translations model catalog from Mozilla Remote
      # Settings and downloads language packs (model + vocabulary) with
      # sha256 verification into the model store.
      #
      # Catalog policy: for every language pair the newest release whose
      # files the engine supports (one shared SentencePiece vocabulary) is
      # offered; alpha versions lose to releases. Pairs published only with
      # split source/target vocabularies are not offered.
      class ModelCatalogService < Shoko::Adapters::BaseAdapter
        RECORDS_URL =
          'https://firefox.settings.services.mozilla.com/v1/buckets/main/collections/translations-models/records'
        ATTACHMENT_BASE_URL = 'https://firefox-settings-attachments.cdn.mozilla.net/'

        class CatalogError < Shoko::Error; end

        RemoteFile = Data.define(:name, :url, :size, :sha256)
        RemotePack = Data.define(:from, :to, :version, :model, :vocab) do
          def total_size
            model.size + vocab.size
          end
        end

        def initialize(records_url: RECORDS_URL, attachment_base_url: ATTACHMENT_BASE_URL, logger: nil)
          super(logger: logger)
          @records_url = records_url
          @attachment_base_url = attachment_base_url
        end

        # Returns [RemotePack], sorted by language pair.
        def list_remote
          records = fetch_records
          build_packs(records).sort_by { |pack| [pack.from, pack.to] }
        end

        # Downloads a pack's files into the store and writes the manifest.
        # Yields (received_bytes, total_bytes) across both files.
        def download(pack, model_store, &)
          dir = model_store.create_pack_dir(pack.from, pack.to)
          download_pack_files(pack, dir, &)
          model_store.write_manifest(
            pack.from, pack.to,
            version: pack.version,
            model_file: pack.model.name,
            vocab_file: pack.vocab.name
          )
        end

        private

        def download_pack_files(pack, dir)
          total = pack.total_size
          received = 0
          [pack.model, pack.vocab].each do |file|
            dest = File.join(dir, File.basename(file.name))
            base = received
            download_file(file, dest) { |done| yield(base + done, total) if block_given? }
            received += file.size
          end
        end

        # --- catalog ----------------------------------------------------------

        def fetch_records
          body = http_get_body(@records_url)
          parsed = JSON.parse(body, symbolize_names: true)
          data = parsed[:data]
          raise CatalogError, 'Malformed catalog response' unless data.is_a?(Array)

          data
        rescue JSON::ParserError => e
          raise CatalogError, "Malformed catalog response: #{e.message}"
        end

        def build_packs(records)
          by_pair = records.group_by { |r| [r[:fromLang].to_s, r[:toLang].to_s] }
          by_pair.filter_map do |(from, to), pair_records|
            next if from.empty? || to.empty?

            best_supported_release(from, to, pair_records)
          end
        end

        def best_supported_release(from, to, records)
          by_version = records.group_by { |r| r[:version].to_s }
          candidates = by_version.filter_map do |version, files|
            model = attachment_record(files, 'model')
            vocab = attachment_record(files, 'vocab')
            next unless model && vocab

            [version, model, vocab]
          end
          version, model, vocab = candidates.max_by { |candidate| version_key(candidate[0]) }
          return nil unless version

          RemotePack.new(
            from: from, to: to, version: version,
            model: remote_file(model), vocab: remote_file(vocab)
          )
        end

        def attachment_record(files, file_type)
          files.find { |r| r[:fileType].to_s == file_type && r.dig(:attachment, :location) }
        end

        def remote_file(record)
          attachment = record[:attachment]
          RemoteFile.new(
            name: record[:name].to_s,
            url: URI.join(@attachment_base_url, attachment[:location].to_s).to_s,
            size: attachment[:size].to_i,
            sha256: attachment[:hash].to_s
          )
        end

        # Releases sort above their own alphas: "1.0a1" < "1.0" < "2.1".
        def version_key(version)
          match = version.match(/\A(\d+)\.(\d+)([a-z].*)?\z/)
          return [0, 0, 0] unless match

          [match[1].to_i, match[2].to_i, match[3] ? 0 : 1]
        end

        # --- downloads --------------------------------------------------------

        def download_file(file, dest_path, &)
          return if File.file?(dest_path) && digest_matches?(dest_path, file.sha256)

          part_path = "#{dest_path}.part"
          digest = Digest::SHA256.new
          stream_to_file(file.url, part_path, digest, &)
          unless file.sha256.empty? || digest.hexdigest == file.sha256
            raise CatalogError, "Checksum mismatch for #{file.name}"
          end

          File.rename(part_path, dest_path)
        ensure
          FileUtils.rm_f(part_path) if part_path
        end

        def digest_matches?(path, sha256)
          return false if sha256.empty?

          Digest::SHA256.file(path).hexdigest == sha256
        end

        def stream_to_file(url, part_path, digest, redirects_left = 2, &)
          uri = parse_http_uri(url)
          received = 0
          with_http(uri) do |http|
            http.request(Net::HTTP::Get.new(uri)) do |response|
              if response.is_a?(Net::HTTPRedirection) && redirects_left.positive?
                redirect = URI.join(uri.to_s, response['location']).to_s
                next stream_to_file(redirect, part_path, digest, redirects_left - 1, &)
              end
              raise CatalogError, "Download failed (#{response.code})" unless response.is_a?(Net::HTTPSuccess)

              write_body(response, part_path, digest, received, &)
            end
          end
        end

        def write_body(response, part_path, digest, received)
          File.open(part_path, 'wb') do |io|
            response.read_body do |chunk|
              io.write(chunk)
              digest.update(chunk)
              received += chunk.bytesize
              yield(received) if block_given?
            end
          end
        end

        def http_get_body(url)
          uri = parse_http_uri(url)
          response = with_http(uri) { |http| http.get(uri.request_uri) }
          raise CatalogError, "Catalog request failed (#{response.code})" unless response.is_a?(Net::HTTPSuccess)

          response.body
        rescue IOError, SystemCallError, SocketError, Timeout::Error => e
          raise CatalogError, "Catalog request failed: #{e.message}"
        end

        def parse_http_uri(url)
          ensure_http_dependencies!
          uri = URI.parse(url.to_s)
          raise CatalogError, "Invalid URL: #{url}" unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

          uri
        rescue URI::InvalidURIError => e
          raise CatalogError, "Invalid URL: #{e.message}"
        end

        def with_http(uri, &)
          ensure_http_dependencies!
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == 'https'
          http.open_timeout = 5
          http.read_timeout = 30
          http.start(&)
        rescue IOError, SystemCallError, SocketError, Timeout::Error => e
          raise CatalogError, "Download failed: #{e.message}"
        end

        def ensure_http_dependencies!
          return if defined?(Net::HTTP) && defined?(URI::DEFAULT_PARSER)

          require 'net/http'
          require 'uri'
        end
      end
    end
  end
end
