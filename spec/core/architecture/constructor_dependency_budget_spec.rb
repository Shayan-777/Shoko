# frozen_string_literal: true

require 'spec_helper'
require 'ripper'

RSpec.describe 'Constructor dependency budget' do
  MAX_TOTAL_PARAMETERS = 12
  MAX_KEYWORD_PARAMETERS = 10

  let(:lib_root) { File.expand_path('../../../lib/shoko', __dir__) }

  def walk(node, &block)
    return unless node.is_a?(Array)

    yield node
    node.each { |child| walk(child, &block) if child.is_a?(Array) }
  end

  def params_for(definition)
    node = definition[2]
    node = node[1] if node&.first == :paren
    node if node&.first == :params
  end

  def counts(params)
    return [0, 0] unless params

    required, optional, rest, post, keywords, keyword_rest, block = params[1..7]
    total = Array(required).length + Array(optional).length + Array(post).length + Array(keywords).length
    total += 1 if rest
    total += 1 if keyword_rest
    total += 1 if block
    [total, Array(keywords).length + (keyword_rest ? 1 : 0)]
  end

  def budgeted?(path)
    relative = path.delete_prefix("#{lib_root}/")
    relative.start_with?('adapters/input/controllers/',
                         'composition/container_factory/controller_composition/',
                         'application/workflows/menu/')
  end

  it 'parses every production Ruby source and bounds every constructor' do
    offenders = []
    Dir[File.join(lib_root, '**', '*.rb')].sort.each do |path|
      source = File.read(path)
      ast = Ripper.sexp(source)
      raise "Architecture scan could not parse #{path}" unless ast
      next unless budgeted?(path)

      walk(ast) do |node|
        next unless node.first == :def && node.dig(1, 1) == 'initialize'

        total, keywords = counts(params_for(node))
        next if total <= MAX_TOTAL_PARAMETERS && keywords <= MAX_KEYWORD_PARAMETERS

        line = node.dig(1, 2, 0)
        relative = path.delete_prefix("#{lib_root}/")
        offenders << "#{relative}:#{line} total=#{total} keyword=#{keywords}"
      end
    end

    expect(offenders).to be_empty,
                         "Oversized constructors (max total 12 / keyword 10):\n#{offenders.join("\n")}"
  end

  it 'forbids untyped initialize(**deps) bags in controllers and workflows' do
    roots = %w[adapters/input/controllers application/workflows].map { |dir| File.join(lib_root, dir) }
    offenders = roots.flat_map { |root| Dir[File.join(root, '**', '*.rb')] }.select do |path|
      File.read(path).match?(/def initialize\s*\([^)]*\*\*deps/)
    end

    expect(offenders).to be_empty
  end
end
