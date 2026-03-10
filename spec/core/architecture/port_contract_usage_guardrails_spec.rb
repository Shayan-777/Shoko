# frozen_string_literal: true

require 'spec_helper'
require 'set'

RSpec.describe 'Application session contract usage' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:lib_root) { File.join(root, 'lib', 'shoko') }
  let(:application_files) { Dir[File.join(lib_root, 'application', '**', '*.rb')] }
  let(:use_case_files) { Dir[File.join(lib_root, 'application', 'use_cases', '**', '*.rb')] }
  let(:store_var_pattern) do
    /
      (?<![A-Za-z0-9_])
      @?
      (reader_session_store|menu_session_store|app_config_store)
      \s*&?\.\s*
      ([A-Za-z_][A-Za-z0-9_]*[!?=]?)
    /x
  end
  let(:snapshot_var_pattern) do
    /
      (?<![A-Za-z0-9_])
      @?
      (current_reader|reader_snapshot|current_menu|menu_snapshot|current_config|config_snapshot)
      \s*&?\.\s*
      ([A-Za-z_][A-Za-z0-9_]*[!?=]?)
    /x
  end

  def port_methods(port_module)
    port_module.instance_methods(false).map(&:to_s).to_set
  end

  def snapshot_methods(snapshot_class, fields)
    (fields.map(&:to_s) + snapshot_class.instance_methods(false).map(&:to_s)).to_set
  end

  def allowed_store_methods
    generic_object_methods = Set.new(%w[is_a? nil?])

    {
      'reader_session_store' => port_methods(Shoko::Core::Ports::Outbound::ReaderSessionStore) + generic_object_methods,
      'menu_session_store' => port_methods(Shoko::Core::Ports::Outbound::MenuSessionStore) + generic_object_methods,
      'app_config_store' => port_methods(Shoko::Core::Ports::Outbound::AppConfigStore) + generic_object_methods
    }
  end

  def allowed_snapshot_methods
    {
      'current_reader' => snapshot_methods(Shoko::Core::Models::Session::ReaderSnapshot,
                                           Shoko::Core::Models::Session::ReaderSnapshotFields),
      'reader_snapshot' => snapshot_methods(Shoko::Core::Models::Session::ReaderSnapshot,
                                            Shoko::Core::Models::Session::ReaderSnapshotFields),
      'current_menu' => snapshot_methods(Shoko::Core::Models::Session::MenuSnapshot,
                                         Shoko::Core::Models::Session::MenuSnapshotFields),
      'menu_snapshot' => snapshot_methods(Shoko::Core::Models::Session::MenuSnapshot,
                                          Shoko::Core::Models::Session::MenuSnapshotFields),
      'current_config' => snapshot_methods(Shoko::Core::Models::Session::ConfigSnapshot,
                                           Shoko::Core::Models::Session::ConfigSnapshotFields),
      'config_snapshot' => snapshot_methods(Shoko::Core::Models::Session::ConfigSnapshot,
                                            Shoko::Core::Models::Session::ConfigSnapshotFields)
    }
  end

  def collect_offenders(pattern, allowed_map)
    offenders = []

    application_files.each do |path|
      File.readlines(path).each_with_index do |line, index|
        content = line.sub(/\s+#.*\z/, '')
        next if content.strip.empty?

        content.to_enum(:scan, pattern).map { Regexp.last_match }.each do |match|
          receiver = match[1]
          method_name = match[2]
          next if allowed_map.fetch(receiver).include?(method_name)

          offenders << "#{path}:#{index + 1} #{receiver}.#{method_name}"
        end
      end
    end

    offenders
  end

  it 'limits application-layer store calls to core outbound port methods' do
    offenders = collect_offenders(store_var_pattern, allowed_store_methods)

    expect(offenders).to eq([]),
                         "Application calls methods outside core store port contracts:\n#{offenders.sort.join("\n")}"
  end

  it 'limits application-layer snapshot calls to core snapshot contracts' do
    offenders = collect_offenders(snapshot_var_pattern, allowed_snapshot_methods)

    expect(offenders).to eq([]),
                         "Application calls methods outside core snapshot contracts:\n#{offenders.sort.join("\n")}"
  end

  it 'forbids adapter-local session helper identifiers in application files' do
    pattern = /\b(reader_state_reader|sidebar_state_reader|ui_state_reader|menu_state_reader|reader_session_mutator|menu_session_mutator)\b/
    offenders = use_case_files.select do |path|
      non_comment_content = File.readlines(path).reject { |line| line.strip.start_with?('#') }.join
      non_comment_content.match?(pattern)
    end

    expect(offenders).to eq([]),
                         "Application still references adapter-local session helpers:\n#{offenders.sort.join("\n")}"
  end
end
