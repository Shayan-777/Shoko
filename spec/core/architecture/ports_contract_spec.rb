# frozen_string_literal: true

require 'spec_helper'
require 'set'

# Consolidated port-contract rules (constitution §V): the inbound/outbound
# boundary is real, every interface port has a production implementer, the
# intent contract stays aligned, and application code talks to the boundary
# only through port methods. Absorbs the former no_orphan_ports,
# port_contract_usage, command_bus, intent_runtime_port and
# application_session_helper suites plus the intent-alignment and dispatch
# examples of the retired fail_fast/zero_fallback suites.
RSpec.describe 'Ports contract' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:lib_root) { File.join(root, 'lib', 'shoko') }
  let(:ports_root) { File.join(lib_root, 'application', 'ports') }
  let(:reader_builder_paths) do
    Dir[File.join(lib_root, 'composition', 'container_factory', 'controller_composition', 'reader_builder', '*.rb')]
  end
  let(:menu_builder_path) do
    File.join(lib_root, 'composition', 'container_factory', 'controller_composition', 'menu_builder.rb')
  end

  def non_comment_content(path)
    File.readlines(path).reject { |line| line.strip.start_with?('#') }.join
  rescue StandardError
    ''
  end

  def rel(path)
    path.delete_prefix("#{lib_root}/")
  end

  describe 'port layout' do
    it 'keeps ports application-owned under inbound/outbound only' do
      core_ports_root = File.join(lib_root, 'core', 'ports')
      inbound = File.join(ports_root, 'inbound')
      outbound = File.join(ports_root, 'outbound')

      expect(Dir.exist?(core_ports_root)).to eq(false), "Core ports must not exist: #{core_ports_root}"
      expect(Dir.exist?(inbound)).to eq(true), "Missing inbound ports directory: #{inbound}"
      expect(Dir.exist?(outbound)).to eq(true), "Missing outbound ports directory: #{outbound}"

      unexpected_dirs = Dir[File.join(ports_root, '*')].select do |path|
        File.directory?(path) && !%w[inbound outbound].include?(File.basename(path))
      end
      root_files = Dir[File.join(ports_root, '*.rb')]

      expect(unexpected_dirs + root_files).to be_empty,
                                              "Non-canonical application/ports artifacts found:\n#{(unexpected_dirs + root_files).join("\n")}"
    end
  end

  describe 'implementers' do
    # Every *interface* port — a module that declares its contract through
    # `raise NotImplementedError` stubs — must have at least one PRODUCTION
    # implementer. A port with no production implementer is an orphan (a
    # contract honoured only by test doubles) that silently drifts from
    # reality. See audit ARCH-6. Only the implementer side is enforced:
    # consumers call duck-typed collaborators, so a production `include` is
    # the reliable, false-positive-free signal.
    it 'requires every interface port to have a production implementer (includer)' do
      interface_ports = Dir[File.join(ports_root, '{inbound,outbound}', '**', '*.rb')].select do |path|
        non_comment_content(path).include?('NotImplementedError')
      end
      expect(interface_ports).not_to be_empty, 'No interface ports found — glob or layout changed.'

      production_contents = Dir[File.join(lib_root, '**', '*.rb')]
                            .reject { |path| path.start_with?("#{ports_root}/") }
                            .map { |path| non_comment_content(path) }

      offenders = interface_ports.filter_map do |path|
        name = interface_port_module_name(non_comment_content(path))
        next "#{rel(path)} (could not determine port module name)" if name.nil?

        include_pattern = /\binclude\b[^\n]*(?<![A-Za-z0-9_])#{Regexp.escape(name)}(?![A-Za-z0-9_])/
        next if production_contents.any? { |content| content.match?(include_pattern) }

        "#{rel(path)} (port #{name} has no production `include`r)"
      end

      expect(offenders).to be_empty,
                           "Orphan interface ports — defined but never implemented in production:\n#{offenders.sort.join("\n")}"
    end

    it 'forbids controller includes of inbound ports' do
      controller_files = Dir[File.join(lib_root, 'adapters', 'input', 'controllers', '**', '*.rb')]
      offenders = controller_files.select do |path|
        non_comment_content(path).include?('include Shoko::Application::Ports::Inbound::')
      end

      expect(offenders).to eq([]),
                           "Controllers still include inbound ports:\n#{offenders.join("\n")}"
    end
  end

  describe 'intent contract' do
    it 'keeps menu intent action groups exactly aligned with inbound intent symbols' do
      expected = Shoko::Application::Ports::Inbound::MenuIntentHandler::INTENT_SYMBOLS.sort
      actual = (
        Shoko::Application::UseCases::Menu::Actions::Navigation::SUPPORTED_INTENTS +
        Shoko::Application::UseCases::Menu::Actions::Browse::SUPPORTED_INTENTS +
        Shoko::Application::UseCases::Menu::Actions::Search::SUPPORTED_INTENTS +
        Shoko::Application::UseCases::Menu::Actions::Dictionary::SUPPORTED_INTENTS +
        Shoko::Application::UseCases::Menu::Actions::TranslatorPacks::SUPPORTED_INTENTS +
        Shoko::Application::UseCases::Menu::Actions::Download::SUPPORTED_INTENTS +
        Shoko::Application::UseCases::Menu::Actions::Translator::SUPPORTED_INTENTS +
        Shoko::Application::UseCases::Menu::Actions::RssReader::SUPPORTED_INTENTS +
        Shoko::Application::UseCases::Menu::Actions::Annotations::SUPPORTED_INTENTS +
        Shoko::Application::UseCases::Menu::Actions::Settings::SUPPORTED_INTENTS +
        Shoko::Application::UseCases::Menu::Actions::Lifecycle::SUPPORTED_INTENTS
      ).uniq.sort
      expect(actual).to eq(expected)
    end

    it 'keeps reader intent action groups exactly aligned with inbound intent symbols' do
      expected = Shoko::Application::Ports::Inbound::ReaderIntentHandler::INTENT_SYMBOLS.sort
      actual = (
        Shoko::Application::UseCases::Reader::Actions::Navigation::SUPPORTED_INTENTS +
        Shoko::Application::UseCases::Reader::Actions::Overlay::SUPPORTED_INTENTS +
        Shoko::Application::UseCases::Reader::Actions::Dictionary::SUPPORTED_INTENTS +
        Shoko::Application::UseCases::Reader::Actions::Search::SUPPORTED_INTENTS +
        Shoko::Application::UseCases::Reader::Actions::Toc::SUPPORTED_INTENTS +
        Shoko::Application::UseCases::Reader::Actions::Translator::SUPPORTED_INTENTS +
        Shoko::Application::UseCases::Reader::Actions::Notes::SUPPORTED_INTENTS +
        Shoko::Application::UseCases::Reader::Actions::AnnotationEditor::SUPPORTED_INTENTS +
        Shoko::Application::UseCases::Reader::Actions::Lifecycle::SUPPORTED_INTENTS
      ).uniq.sort
      expect(actual).to eq(expected)
    end

    it 'enforces symbol-only direct intent dispatch contract' do
      dispatcher_content = non_comment_content(File.join(lib_root, 'adapters', 'input', 'dispatcher.rb'))
      reader_handler_content = non_comment_content(File.join(lib_root, 'application', 'use_cases',
                                                             'reader_intent_handler.rb'))
      menu_handler_content = non_comment_content(File.join(lib_root, 'application', 'use_cases',
                                                           'menu_intent_handler.rb'))

      expect(dispatcher_content).to include('binding.is_a?(Symbol)')
      expect(dispatcher_content).not_to match(/\bexecute_proc\b|\bexecute_object\b|\bexecutable_command\?\b/)
      expect(reader_handler_content).to include('intent_symbol.to_sym')
      expect(menu_handler_content).to include('intent_symbol.to_sym')
    end

    it 'forbids controller loopback in application intent handlers' do
      files = [
        File.join(lib_root, 'application', 'use_cases', 'reader_intent_handler.rb'),
        File.join(lib_root, 'application', 'use_cases', 'menu_intent_handler.rb'),
      ]
      pattern = /@reader_controller\.|@menu_controller\.|reader_controller:|menu_controller:/
      offenders = files.select { |path| non_comment_content(path).match?(pattern) }

      expect(offenders).to eq([]),
                           "Application intent handlers still contain controller loopback:\n#{offenders.map { |p| rel(p) }.join("\n")}"
    end
  end

  describe 'intent handler wiring' do
    it 'wires ReaderIntentHandler through session stores and capability ports' do
      content = reader_builder_paths.map { |path| non_comment_content(path) }.join("\n")

      expect(content).to match(/ReaderIntentHandler\.new\([^)]*reader_session_store:/m),
                         'Reader intent handler must be wired with reader_session_store in reader_builder/'
      expect(content).to match(/ReaderIntentHandler\.new\([^)]*reader_overlay_control:/m),
                         'Reader intent handler must be wired with capability ports in reader_builder/'
      expect(content).to match(/ReaderIntentHandler\.new\([^)]*application_exit_control:/m),
                         'Reader intent handler must receive application_exit_control in reader_builder/'
      expect(content).not_to match(/ReaderIntentHandler\.new\([^)]*reader_state_reader:/m),
                             'Reader intent handler must not receive reader_state_reader in reader_builder/'
      expect(content).not_to match(/ReaderIntentHandler\.new\([^)]*reader_runtime:/m),
                             'Reader intent handler must not receive reader_runtime in reader_builder/'
    end

    it 'wires MenuIntentHandler through session stores and capability ports' do
      content = non_comment_content(menu_builder_path)

      expect(content).to match(/MenuIntentHandler\.new\([^)]*menu_session_store:/m),
                         "Menu intent handler must be wired with menu_session_store: #{menu_builder_path}"
      expect(content).to match(/MenuIntentHandler\.new\([^)]*application_exit_control:/m),
                         "Menu intent handler must receive application_exit_control: #{menu_builder_path}"
      expect(content).not_to match(/MenuIntentHandler\.new\([^)]*menu_state_reader:/m),
                             "Menu intent handler must not receive menu_state_reader: #{menu_builder_path}"
      expect(content).not_to match(/MenuIntentHandler\.new\([^)]*menu_session_mutator:/m),
                             "Menu intent handler must not receive menu_session_mutator: #{menu_builder_path}"
      expect(content).not_to match(/MenuIntentHandler\.new\([^)]*menu_runtime:/m),
                             "Menu intent handler must not receive menu_runtime: #{menu_builder_path}"
    end
  end

  describe 'contract usage in the application layer' do
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
        'reader_session_store' => port_methods(Shoko::Application::Ports::Outbound::ReaderSessionStore) + generic_object_methods,
        'menu_session_store' => port_methods(Shoko::Application::Ports::Outbound::MenuSessionStore) + generic_object_methods,
        'app_config_store' => port_methods(Shoko::Application::Ports::Outbound::AppConfigStore) + generic_object_methods,
      }
    end

    def allowed_snapshot_methods
      {
        'current_reader' => snapshot_methods(Shoko::Application::Ports::Outbound::State::ReaderSnapshot,
                                             Shoko::Application::Ports::Outbound::State::ReaderSnapshot::FIELDS),
        'reader_snapshot' => snapshot_methods(Shoko::Application::Ports::Outbound::State::ReaderSnapshot,
                                              Shoko::Application::Ports::Outbound::State::ReaderSnapshot::FIELDS),
        'current_menu' => snapshot_methods(Shoko::Application::Ports::Outbound::State::MenuSnapshot,
                                           Shoko::Application::Ports::Outbound::State::MenuSnapshot::FIELDS),
        'menu_snapshot' => snapshot_methods(Shoko::Application::Ports::Outbound::State::MenuSnapshot,
                                            Shoko::Application::Ports::Outbound::State::MenuSnapshot::FIELDS),
        'current_config' => snapshot_methods(Shoko::Application::Ports::Outbound::State::ConfigSnapshot,
                                             Shoko::Application::Ports::Outbound::State::ConfigSnapshot::FIELDS),
        'config_snapshot' => snapshot_methods(Shoko::Application::Ports::Outbound::State::ConfigSnapshot,
                                              Shoko::Application::Ports::Outbound::State::ConfigSnapshot::FIELDS),
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

    it 'forbids adapter-local session helper identifiers in application use cases' do
      pattern = /\b(reader_state_reader|sidebar_state_reader|ui_state_reader|menu_state_reader|reader_session_mutator|menu_session_mutator)\b/
      offenders = use_case_files.select do |path|
        non_comment_content(path).match?(pattern)
      end

      expect(offenders).to eq([]),
                           "Application still references adapter-local session helpers:\n#{offenders.sort.join("\n")}"
    end
  end

  def interface_port_module_name(content)
    preamble = content.split('NotImplementedError', 2).first
    preamble.to_s.scan(/^\s*module\s+([A-Z]\w+)/).flatten.last
  end
end
