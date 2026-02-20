# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Constructor dependency budget' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:lib_root) { File.join(root, 'lib', 'shoko') }

  MAX_TOTAL_PARAMS = 12
  MAX_KEYWORD_PARAMS = 10

  def relative(path)
    path.delete_prefix("#{lib_root}/")
  end

  def target_files
    Dir[File.join(lib_root, 'adapters', 'input', 'controllers', '**', '*.rb')] +
      Dir[File.join(lib_root, 'bootstrap', 'container_factory', 'controller_composition', '**', '*.rb')] +
      Dir[File.join(lib_root, 'application', 'workflows', 'menu', '**', '*.rb')]
  end

  def initialize_signatures(path)
    lines = File.readlines(path)
    signatures = []
    index = 0

    while index < lines.length
      line = lines[index]
      match = line.match(/^\s*def\s+initialize\s*\(/)
      unless match
        index += 1
        next
      end

      signature_start = index + 1
      start_col = match.end(0)
      capture = line[start_col..] || ''
      depth = 1
      index += 1

      while index < lines.length && depth.positive?
        segment = lines[index]
        capture << segment
        depth += segment.count('(')
        depth -= segment.count(')')
        index += 1
      end

      params = capture.sub(/\)\s*(?:=.*)?\z/m, '')
      signatures << {
        line: signature_start,
        params: params,
      }
    end

    signatures
  rescue StandardError
    []
  end

  def split_top_level_params(params)
    tokens = []
    current = +''
    paren_depth = 0
    bracket_depth = 0
    brace_depth = 0
    quote = nil
    escape = false

    params.each_char do |char|
      if quote
        current << char
        if escape
          escape = false
        elsif char == '\\'
          escape = true
        elsif char == quote
          quote = nil
        end
        next
      end

      if char == "'" || char == '"'
        quote = char
        current << char
        next
      end

      case char
      when '('
        paren_depth += 1
        current << char
      when ')'
        paren_depth -= 1 if paren_depth.positive?
        current << char
      when '['
        bracket_depth += 1
        current << char
      when ']'
        bracket_depth -= 1 if bracket_depth.positive?
        current << char
      when '{'
        brace_depth += 1
        current << char
      when '}'
        brace_depth -= 1 if brace_depth.positive?
        current << char
      when ','
        if paren_depth.zero? && bracket_depth.zero? && brace_depth.zero?
          token = current.strip
          tokens << token unless token.empty?
          current = +''
        else
          current << char
        end
      else
        current << char
      end
    end

    tail = current.strip
    tokens << tail unless tail.empty?
    tokens
  end

  def keyword_param?(token)
    token.match?(/\A[a-zA-Z_]\w*:/)
  end

  def constructor_stats(path)
    initialize_signatures(path).map do |signature|
      tokens = split_top_level_params(signature[:params])
      keyword_count = tokens.count { |token| keyword_param?(token) }
      {
        file: relative(path),
        line: signature[:line],
        total: tokens.size,
        keyword: keyword_count,
        raw: tokens.join(', '),
      }
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

    expect(offenders).to be_empty,
                             "Oversized initialize signatures exceed budget (max total=#{MAX_TOTAL_PARAMS}, max keyword=#{MAX_KEYWORD_PARAMS}):\n#{offenders.sort.join("\n")}"
  end
end
