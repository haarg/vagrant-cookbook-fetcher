# -*-ruby-*-
Gem::Specification.new do |s|
  s.name        = 'vagrant-cookbook-fetcher'
  s.version     = '0.0.5'
  s.date        = '2012-09-21'
  s.summary     = "Fetch your Chef cookbooks whenever you provision"
  s.description = "Whenever you run start, up, or provision, this plugin will dynamically fetch a list of checkouts from a URL; checkout each one; then create a combined roles directory, with symlinks."
  s.authors     = ["Clinton Wolfe"]
  s.email       = 'clinton@NOSPAM.omniti.com'
  s.files       = [
                   "LICENSE",
                   "README.md",
                   "lib/vagrant_init.rb",
                   "lib/vagrant_cookbook_fetcher.rb",
                  ]
  s.homepage    =
    'https://github.com/clintoncwolfe/vagrant-cookbook-fetcher'
end
