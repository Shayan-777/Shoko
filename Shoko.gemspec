# frozen_string_literal: true

require_relative 'lib/shoko/shared/version'

Gem::Specification.new do |spec|
  spec.name = 'shoko'
  spec.version = Shoko::VERSION
  spec.authors = ['Shoko']
  spec.email = ['ruby.computer770@passinbox.com']

  spec.summary = 'Terminal EBook Reader'
  spec.description = 'Terminal EBook Reader'
  spec.homepage = 'https://sr.ht/~shayan/Shoko/'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.4'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage

  # Specify which files should be added to the gem
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      f.end_with?('.gem') ||
        (f == __FILE__) ||
        f.match(%r{\A(?:(?:bin|test|spec|features)/|\.(?:git|circleci)|appveyor)})
    end.select { |f| File.file?(f) }
  end
  spec.bindir = 'bin'
  spec.executables = %w[shoko]
  spec.require_paths = ['lib']

  # Development dependencies are managed in the Gemfile
  spec.metadata['rubygems_mfa_required'] = 'true'
end
