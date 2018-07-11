lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "trailblazer/disposable/version"

Gem::Specification.new do |spec|
  spec.name          = "trailblazer-disposable"
  spec.version       = Trailblazer::Disposable::VERSION
  spec.authors       = ["Nick Sutterer"]
  spec.email         = ["apotonick@gmail.com"]

  spec.summary       = %q{Domain object layer.}
  # spec.description   = %q{TODO: Write a longer description or delete this line.}
  spec.homepage      = "http://trailblazer.to"

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.16"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "minitest-line"

  spec.add_dependency "declarative" # DISCUSS: we might remove this dependency.
  spec.add_dependency "dry-struct" # DISCUSS: we might remove this dependency.
end
