# frozen_string_literal: true

module SpecSupport
  module Architecture
    # Detects class fragments: a class whose body receives direct method
    # definitions from two or more files. Reopening a class to add methods is
    # the include-once mixin through a different door — the indirection of
    # decomposition with none of its benefits, invisible to the include
    # scanner because no `include` ever appears (constitution R1/R3; §III
    # requires a file to be named after the single constant it defines).
    #
    # Legitimate multi-file layouts are NOT flagged:
    #   * a file that reopens a class purely as a namespace to define a nested
    #     collaborator class/module (the nested constant owns the defs);
    #   * nested `Struct.new`/`Data.define` types with block-body methods
    #     (their defs sit deeper than one level below the class declaration).
    #
    # Detection is indentation-based (2-space, rubocop-enforced), matching the
    # rest of the architecture suite: a def belongs directly to a class when it
    # is exactly one level below the class declaration, or one level below a
    # `class << self` that is itself one level below the declaration.
    module ClassReopeningScanner
      module_function

      DECL_PATTERN = /^(\s*)(class|module)\s+([A-Z][\w:]*)/.freeze
      SINGLETON_PATTERN = /^(\s*)class\s*<<\s*self\b/.freeze
      DEF_PATTERN = /^(\s*)def\s/.freeze

      # @return [Array<String>] "Fq::Class::Name (file_a, file_b, ...)" for
      #   every class with direct defs in two or more files.
      def violations(lib_root)
        defining_files = Hash.new { |h, k| h[k] = [] }

        Dir[File.join(lib_root, '**', '*.rb')].sort.each do |path|
          rel = path.delete_prefix("#{lib_root}/")
          direct_def_owners(non_comment_lines(path)).each do |fqn|
            defining_files[fqn] << rel unless defining_files[fqn].include?(rel)
          end
        end

        defining_files.select { |_fqn, files| files.length >= 2 }
                      .map { |fqn, files| "#{fqn} (#{files.join(', ')})" }
                      .sort
      end

      # Fully-qualified names of classes/modules that receive direct method
      # definitions in this file.
      def direct_def_owners(lines)
        stack = [] # [indent, kind(:class/:module/:singleton), name]
        owners = []

        lines.each do |line|
          if (m = line.match(SINGLETON_PATTERN))
            pop_to(stack, m[1].length)
            stack << [m[1].length, :singleton, '<<self']
          elsif (m = line.match(DECL_PATTERN))
            pop_to(stack, m[1].length)
            stack << [m[1].length, m[2] == 'class' ? :class : :module, m[3]]
          elsif (m = line.match(DEF_PATTERN))
            fqn = direct_class_owner(stack, m[1].length)
            owners << fqn if fqn && !owners.include?(fqn)
          end
        end

        owners
      end

      # The class/module that directly owns a def at +indent+, or nil when the
      # def belongs to a nested block type or nothing on the stack.
      def direct_class_owner(stack, indent)
        pop_to(stack, indent)
        owner_index = stack.length - 1
        owner = stack[owner_index]
        return nil unless owner

        if owner[1] == :singleton
          singleton_indent = owner[0]
          owner_index -= 1
          owner = stack[owner_index]
          return nil unless owner && %i[class module].include?(owner[1])
          return nil unless singleton_indent == owner[0] + 2 && indent == singleton_indent + 2
        else
          return nil unless %i[class module].include?(owner[1]) && indent == owner[0] + 2
        end

        stack[..owner_index].map { |entry| entry[2] }.join('::')
      end

      def pop_to(stack, indent)
        stack.pop while stack.last && stack.last[0] >= indent
      end

      def non_comment_lines(path)
        File.readlines(path).reject { |line| line.strip.start_with?('#') }
      rescue StandardError
        []
      end
    end
  end
end
