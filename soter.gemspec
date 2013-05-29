Gem::Specification.new do |s|
  s.name        = 'soter'
  s.version     = '0.0.1'
  s.summary     = "Background jobs"
  s.description = "ruby + mongoid background jobs library"
  s.authors     = %w(andresf solojavier)
  s.email       = '1.27201@gmail.com'
  s.files       = Dir['lib/soter/*.rb'] + %w(lib/soter.rb) 

  s.add_development_dependency('rspec')
  s.add_development_dependency('rake')
  s.add_dependency('moped')
end
