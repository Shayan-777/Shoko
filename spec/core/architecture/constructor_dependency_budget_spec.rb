# frozen_string_literal: true

require 'spec_helper'
require 'ripper'

MAX_TOTAL_PARAMS = 12
MAX_KEYWORD_PARAMS = 10

RSpec.describe 'Constructor dependency budget' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:lib_root) { File.join(root, 'lib', 'shoko') }

  def relative(path)
    path.delete_prefix("#{lib_root}/")
  end

  def target_files
    Dir[File.join(lib_root, 'adapters', 'input', 'controllers', '**', '*.rb')] +
      Dir[File.join(lib_root, 'composition', 'container_factory', 'controller_composition', '**', '*.rb')] +
      Dir[File.join(lib_root, 'application', 'workflows', 'menu', '**', '*.rb')]
  end

  def constructor_stats(path)
    source = File.read(path)
    ast = Ripper.sexp(source)
    return [] unless ast

    extract_initialize_defs(ast).map do |definition|
      stats = parameter_stats(definition[:params])
      {
        file: relative(path),
        line: definition[:line],
        total: stats[:total],
        keyword: stats[:keyword],
        raw: stats[:raw],
      }
    end
  rescue StandardError
    []
  end

  def extract_initialize_defs(node, acc = [])
    return acc unless node.is_a?(Array)

    if node[0] == :def && initialize_name_node?(node[1])
      params_node = unwrap_params(node[2])
      line = node[1][2][0]
      acc << { line: line, params: params_node }
    end

    node.each do |child|
      extract_initialize_defs(child, acc) if child.is_a?(Array)
    end

    acc
  end

  def initialize_name_node?(node)
    node.is_a?(Array) && node[0] == :@ident && node[1] == 'initialize'
  end

  def unwrap_params(node)
    return nil unless node.is_a?(Array)
    return node[1] if node[0] == :paren
    return node if node[0] == :params

    nil
  end

  def parameter_stats(params_node)
    return { total: 0, keyword: 0, raw: '' } unless params_node.is_a?(Array) && params_node[0] == :params

    required = params_node[1]
    optional = params_node[2]
    rest = params_node[3]
    post = params_node[4]
    keywords = params_node[5]
    kwrest = params_node[6]
    block = params_node[7]

    tokens = []
    keyword_count = 0

    tokens.concat(extract_identifier_list(required))
    tokens.concat(extract_optional_list(optional))

    if rest
      name = extract_name(rest)
      tokens << (name.empty? ? '*' : "*#{name}")
    end

    tokens.concat(extract_identifier_list(post))

    keyword_tokens = extract_keyword_list(keywords)
    tokens.concat(keyword_tokens)
    keyword_count += keyword_tokens.length

    if kwrest
      name = extract_name(kwrest)
      tokens << (name.empty? ? '**' : "**#{name}")
      keyword_count += 1
    end

    if block
      name = extract_name(block)
      tokens << (name.empty? ? '&' : "&#{name}")
    end

    { total: tokens.length, keyword: keyword_count, raw: tokens.join(', ') }
  end

  def extract_identifier_list(nodes)
    return [] unless nodes.is_a?(Array)

    nodes.filter_map do |node|
      name = extract_name(node)
      name unless name.empty?
    end
  end

  def extract_optional_list(nodes)
    return [] unless nodes.is_a?(Array)

    nodes.filter_map do |node|
      lhs = node.is_a?(Array) ? node[0] : node
      name = extract_name(lhs)
      name unless name.empty?
    end
  end

  def extract_keyword_list(nodes)
    return [] unless nodes.is_a?(Array)

    nodes.filter_map do |node|
      label_node = node.is_a?(Array) ? node[0] : node
      name = extract_name(label_node)
      next if name.empty?

      "#{name}:"
    end
  end

  def extract_name(node)
    return '' unless node.is_a?(Array)

    case node[0]
    when :@ident
      node[1].to_s
    when :@label
      node[1].to_s.delete_suffix(':')
    when :rest_param, :kwrest_param, :blockarg, :var_field
      extract_name(node[1])
    else
      ''
    end
  end

  it 'limits constructor arity in controller and wiring classes' do
    offenders = target_files.flat_map do |path|
      constructor_stats(path).filter_map do |stats|
        over_total = stats[:total] > MAX_TOTAL_PARAMS
        over_keyword = stats[:keyword] > MAX_KEYWORD_PARAMS
        next unless over_total || over_keyword

        "#{stats[:file]}:#{stats[:line]} total=#{stats[:total]} keyword=#{stats[:keyword]} :: #{stats[:raw]}"
      end
    end

    expect(offenders).to be_empty, <<~MSG
      Oversized initialize signatures exceed budget (max total=#{MAX_TOTAL_PARAMS}, max keyword=#{MAX_KEYWORD_PARAMS}):
      #{offenders.sort.join("\n")}
    MSG
  end

  it 'keeps critical dependency objects bounded and cohesive' do
    budgets = {
      Shoko::Adapters::Input::Controllers::Menu::StateController::Dependencies => 4,
      Shoko::Application::Workflows::Menu::ReaderLaunchService::Dependencies => 10,
      Shoko::Adapters::Input::Controllers::Menu::Controller::RuntimeDependencies => 7,
      Shoko::Adapters::Input::Controllers::Menu::Controller::BuilderDependencies => 7,
      Shoko::Adapters::Input::Controllers::Menu::Controller::SupportDependencies => 3,
      Shoko::Adapters::Input::Controllers::Dependencies::ReaderControllerCoreDependencies => 8,
      Shoko::Adapters::Input::Controllers::Dependencies::ReaderControllerStateDependencies => 8,
      Shoko::Adapters::Input::Controllers::Dependencies::ReaderControllerServiceDependencies => 8,
      Shoko::Adapters::Input::Controllers::Dependencies::ReaderRuntimeBootDependencies => 8,
      Shoko::Adapters::Input::Controllers::Dependencies::ReaderRuntimeStartupDependencies => 8,
      Shoko::Adapters::Input::Controllers::Dependencies::ReaderMouseDependencies => 8,
      Shoko::Adapters::Input::Controllers::Dependencies::DictionaryControllerDependencies::StateDependencies => 8,
      Shoko::Adapters::Input::Controllers::Dependencies::DictionaryControllerDependencies::ServiceDependencies => 8,
      Shoko::Adapters::Input::Controllers::Dependencies::DictionaryControllerDependencies::UiDependencies => 8,
      Shoko::Adapters::Input::Controllers::Dependencies::DictionaryControllerDependencies::ControllerDependencies => 8,
      Shoko::Adapters::Input::Controllers::Dependencies::StateControllerDependencies::SessionDependencies => 8,
      Shoko::Adapters::Input::Controllers::Dependencies::StateControllerDependencies::DocumentDependencies => 8,
      Shoko::Adapters::Input::Controllers::Dependencies::StateControllerDependencies::ServiceDependencies => 8,
      Shoko::Adapters::Input::Controllers::Dependencies::UiControllerDependencies::StateDependencies => 8,
      # Coordinates the five bar-anchored overlay controllers (search, dictionary,
      # TOC, translator, notes) plus annotation/input/reader.
      Shoko::Adapters::Input::Controllers::Dependencies::UiControllerDependencies::ControllerDependencies => 9,
      Shoko::Adapters::Input::Controllers::Dependencies::UiControllerDependencies::ServiceDependencies => 8,
      Shoko::Adapters::Input::Controllers::Reader::SelectionInteraction::StateDependencies => 4,
      Shoko::Adapters::Input::Controllers::Reader::SelectionInteraction::ServiceDependencies => 7,
      Shoko::Adapters::Input::Controllers::Reader::SelectionInteraction::Callbacks => 4,
    }

    offenders = budgets.filter_map do |klass, max_fields|
      count = klass.members.length
      "#{klass.name} (#{count} > #{max_fields})" if count > max_fields
    end

    expect(offenders).to be_empty, <<~MSG
      Critical dependency objects exceed field budget:
      #{offenders.join("\n")}
    MSG
  end

  # Per-record budgets alone let aggregate coupling hide: a controller can
  # satisfy every record cap while receiving dozens of capabilities across
  # records — or re-bag them into nested records that count as one field.
  # This ratchet counts TRANSITIVE leaf dependencies: record fields are
  # flattened recursively (a field whose name maps to another dependency
  # record contributes that record's own leaf count), plus direct
  # constructor extras. The pins are EXACT actuals, not upper bounds: any
  # change — up or down — fails until the pin is consciously edited, and
  # edits may only ever lower a pin (constitution amendment 2026-07-18).
  #
  # Scope, stated honestly: the audited classes and the nested-record map
  # are ENUMERATED, not derived from constructors — a brand-new coordinating
  # class or nested bag must be added here to be governed. This is a curated
  # review ratchet with exact pins, not universal static analysis.
  # rubocop:disable RSpec/ExampleLength
  it 'pins the aggregate transitive leaf dependencies of the coordinating classes' do
    deps = Shoko::Adapters::Input::Controllers::Dependencies

    # Fields that are themselves dependency records, by record and field name.
    nested_records = {
      deps::ReaderRuntimeBootDependencies => { warmup_services: deps::ReaderWarmupServices },
    }

    flatten_leaves = lambda do |record|
      record.members.sum do |member|
        nested = nested_records.dig(record, member)
        nested ? flatten_leaves.call(nested) : 1
      end
    end

    menu_controller = Shoko::Adapters::Input::Controllers::Menu::Controller
    aggregates = {
      # runtime + builder + support records
      'Menu::Controller' => {
        actual: [menu_controller::RuntimeDependencies, menu_controller::BuilderDependencies,
                 menu_controller::SupportDependencies].sum(&flatten_leaves),
        pinned: 17,
      },
      # six records (warmup_services flattened to its 3 leaves) + direct
      # extras (render_state_writer, mouse_handler, runtime_components_factory)
      'ReaderController' => {
        actual: [
          deps::ReaderControllerCoreDependencies,
          deps::ReaderControllerStateDependencies,
          deps::ReaderControllerServiceDependencies,
          deps::ReaderRuntimeBootDependencies,
          deps::ReaderRuntimeStartupDependencies,
          deps::ReaderMouseDependencies,
        ].sum(&flatten_leaves) + 3,
        pinned: 45,
      },
      # state + controllers + services bundle
      'UIController' => {
        actual: %i[StateDependencies ControllerDependencies ServiceDependencies].sum do |name|
          flatten_leaves.call(deps::UiControllerDependencies.const_get(name))
        end,
        pinned: 19,
      },
      # menu-facing UI component bag
      'MenuUiDependencies' => {
        actual: flatten_leaves.call(Shoko::Adapters::Ui::MenuUiDependencies),
        pinned: 11,
      },
      # render dependencies built at the composition root
      'Reading::RenderDependencies' => {
        actual: flatten_leaves.call(Shoko::Adapters::Ui::Components::Reading::RenderDependencies),
        pinned: 16,
      },
      'Reader::SelectionInteraction' => {
        actual: [
          Shoko::Adapters::Input::Controllers::Reader::SelectionInteraction::StateDependencies,
          Shoko::Adapters::Input::Controllers::Reader::SelectionInteraction::ServiceDependencies,
          Shoko::Adapters::Input::Controllers::Reader::SelectionInteraction::Callbacks,
        ].sum(&flatten_leaves),
        pinned: 15,
      },
    }

    offenders = aggregates.filter_map do |name, entry|
      next if entry[:actual] == entry[:pinned]

      "#{name}: aggregate #{entry[:actual]} != pinned #{entry[:pinned]}"
    end

    expect(offenders).to eq([]), <<~MSG
      Aggregate transitive dependency counts drifted from their pins. Pins may
      only be edited DOWNWARD (after a genuine decoupling); an increase is a
      constitutional violation, and a decrease must be claimed by lowering the
      pin so the ratchet keeps tightening:
      #{offenders.join("\n")}
    MSG
  end
  # rubocop:enable RSpec/ExampleLength

  it 'forbids initialize(**deps) constructors in controllers and workflows' do
    files = Dir[File.join(lib_root, 'adapters', 'input', 'controllers', '**', '*.rb')] +
            Dir[File.join(lib_root, 'application', 'workflows', '**', '*.rb')]
    offenders = files.select do |path|
      File.readlines(path).reject { |line| line.strip.start_with?('#') }.join
          .match?(/def initialize\s*\([^)]*\*\*deps/)
    end

    expect(offenders).to eq([]),
                         "Typed dependency objects are required; found **deps constructors:\n" \
                         "#{offenders.map { |p| relative(p) }.join("\n")}"
  end
end
