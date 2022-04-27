Gem::Specification.new do |s|
  s.name = "fsorg"
  s.version = "0.1.0"
  s.summary = "Create directories from a file that describes them"
  s.authors = ["Ewen Le Bihan"]
  s.email = "hey@ewen.works"
  s.files = ["lib/fsorg.rb"]
  s.homepage = "https://github.com/ewen-lbh/fsorg"
  s.license = "Unlicense"
  s.executables << "fsorg"

  s.required_ruby_version = ">= 3.0.0"
  s.add_dependency "docopt"
  s.add_dependency "shellwords", "~> 0.1.0"
  s.add_dependency "mustache", "~> 1.1"
  s.add_dependency "colorize", "~> 0.8.1"
end
