# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'tmpdir'
require_relative '../../shared/errors'

module Shoko
  module Adapters
    module Translation
      # Storage policy for installed translation language packs.
      #
      # Layout: <config>/translator/models/<from>-<to>/ holding the model
      # binary, the SentencePiece vocabulary and a small pack.json manifest
      # written at install time.
      class ModelStore
        MANIFEST_NAME = 'pack.json'

        InstalledPack = Data.define(:from, :to, :dir, :model_path, :vocab_path, :version)

        def initialize(root:, on_change: nil, logger: nil)
          raise ArgumentError, 'root is required' if root.to_s.empty?

          @root = root
          @on_change = on_change
          @logger = logger
        end

        attr_reader :root

        def installed_packs
          return [] unless Dir.exist?(@root)

          Dir.children(@root).sort.filter_map do |entry|
            read_pack(File.join(@root, entry))
          end
        end

        def installed?(from, to)
          !find(from, to).nil?
        end

        def find(from, to)
          expected_from = normalized_code(from)
          expected_to = normalized_code(to)
          read_pack(pack_dir(expected_from, expected_to), expected_from:, expected_to:)
        end

        def pack_dir(from, to)
          File.join(@root, "#{normalized_code(from)}-#{normalized_code(to)}")
        end

        def create_pack_dir(from, to)
          dir = pack_dir(from, to)
          FileUtils.mkdir_p(dir)
          dir
        end

        def write_manifest(from, to, version:, model_file:, vocab_file:)
          dir = create_pack_dir(from, to)
          validate_file_names!(model_file, vocab_file)
          manifest = manifest_payload(from, to, version:, model_file:, vocab_file:)
          write_manifest_file(dir, manifest)
          manifest
        end

        # Builds a complete pack in a private staging directory and atomically
        # swaps it into place only after every file and the manifest are ready.
        def install(from, to, version:, model_file:, vocab_file:)
          validate_file_names!(model_file, vocab_file)
          FileUtils.mkdir_p(@root)
          stage = Dir.mktmpdir(".#{normalized_code(from)}-#{normalized_code(to)}-", @root)
          yield stage
          manifest = manifest_payload(from, to, version:, model_file:, vocab_file:)
          write_manifest_file(stage, manifest)
          commit_stage(stage, pack_dir(from, to))
          stage = nil
          notify_change(from, to)
          manifest
        ensure
          FileUtils.rm_rf(stage) if stage && File.directory?(stage)
        end

        def remove(from, to)
          dir = pack_dir(from, to)
          FileUtils.rm_rf(dir) if File.directory?(dir)
          notify_change(from, to)
          nil
        end

        private

        def notify_change(from, to)
          @on_change&.call(normalized_code(from), normalized_code(to))
        # resilient-boundary
        rescue StandardError => e
          swallow_pack_change_error(e, from, to)
        end

        def swallow_pack_change_error(error, from, to)
          @logger&.error('translator.pack_change_notification_failed',
                         from: from.to_s, to: to.to_s,
                         error: error.class.name, message: error.message)
        end

        def manifest_payload(from, to, version:, model_file:, vocab_file:)
          {
            from: normalized_code(from),
            to: normalized_code(to),
            version: version.to_s,
            model: File.basename(model_file.to_s),
            vocab: File.basename(vocab_file.to_s),
          }
        end

        def write_manifest_file(dir, manifest)
          path = File.join(dir, MANIFEST_NAME)
          temporary = "#{path}.tmp-#{Process.pid}-#{Thread.current.object_id}"
          File.open(temporary, 'wb') do |io|
            io.write(JSON.pretty_generate(manifest))
            io.flush
            io.fsync
          end
          File.rename(temporary, path)
        ensure
          FileUtils.rm_f(temporary) if temporary && File.exist?(temporary)
        end

        def commit_stage(stage, destination)
          backup = "#{destination}.previous-#{Process.pid}"
          FileUtils.rm_rf(backup)
          File.rename(destination, backup) if File.directory?(destination)
          File.rename(stage, destination)
          FileUtils.rm_rf(backup)
        rescue StandardError
          File.rename(backup, destination) if File.directory?(backup) && !File.exist?(destination)
          raise
        end

        def normalized_code(code)
          value = code.to_s.strip
          return value.downcase if value.match?(/\A[A-Za-z][A-Za-z0-9]*(?:-[A-Za-z0-9]+)*\z/)

          raise ArgumentError, "Invalid translation language code: #{code.inspect}"
        end

        def validate_file_names!(model_file, vocab_file)
          names = [model_file, vocab_file].map(&:to_s)
          valid = names.all? do |name|
            !name.empty? && File.basename(name) == name && !%w[. ..].include?(name)
          end
          raise ArgumentError, 'Translation pack file names must be plain basenames' unless valid
          raise ArgumentError, 'Translation model and vocabulary names must differ' if names.uniq.length != 2
        end

        def read_pack(dir, expected_from: nil, expected_to: nil)
          manifest_path = File.join(dir, MANIFEST_NAME)
          return nil unless File.file?(manifest_path)
          return nil if File.size(manifest_path) > 64 * 1024

          pack = build_pack(dir, JSON.parse(File.read(manifest_path)))
          return nil if expected_from && pack &&
                        (pack.from != expected_from || pack.to != expected_to)

          pack
        # resilient-boundary
        rescue StandardError => e
          swallow_manifest_error(dir, e)
        end

        def build_pack(dir, manifest)
          model_path = File.join(dir, File.basename(manifest.fetch('model', '')))
          vocab_path = File.join(dir, File.basename(manifest.fetch('vocab', '')))
          return nil unless File.file?(model_path) && File.file?(vocab_path)

          InstalledPack.new(
            from: manifest.fetch('from', ''),
            to: manifest.fetch('to', ''),
            dir: dir,
            model_path: model_path,
            vocab_path: vocab_path,
            version: manifest.fetch('version', '')
          )
        end

        # A corrupt pack directory must not take the translator down; the
        # pack simply does not appear as installed.
        def swallow_manifest_error(dir, error)
          @logger&.error('translator.pack_manifest_unreadable',
                         dir: dir, error: error.class.name, message: error.message)
          nil
        end
      end
    end
  end
end
