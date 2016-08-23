Gem::Specification.new do |s|
  s.name        = 'soter'
  s.version     = '0.0.3'
  s.summary     = "Background jobs"
  s.description = "ruby + mongoid background jobs library"
  s.authors     = %w(andresf solojavier)
  s.email       = 'andres@wepow.com'
  s.files       = Dir['lib/soter/*.rb'] + %w(lib/soter.rb)

  s.add_development_dependency('rspec')
  s.add_development_dependency('rake')
  s.add_dependency('moped', '~> 2.0.0')
end
