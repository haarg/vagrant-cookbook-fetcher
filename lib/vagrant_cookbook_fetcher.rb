
# http://vagrantup.com/v1/docs/extending/configuration.html
class CookbookFetcherConfig < Vagrant::Config::Base
  attr_accessor :url
  attr_accessor :disable
end
Vagrant.config_keys.register(:cookbook_fetcher) { CookbookFetcherConfig }


# This is a Vagrant middleware plugin
# http://vagrantup.com/v1/docs/extending/middleware.html

class CookbookFetcher
  def initialize(app, env)
    @app = app
  end

  def call(env)

    if !env[:global_config].cookbook_fetcher.disable then
      if !env[:global_config].cookbook_fetcher.url.nil? then
        fetch_checkouts env
      else
        env[:ui].warn "No URL set for auto-checkout, skipping"
      end
    else
      env[:ui].info "Auto-checkout disabled, skipping"
    end

    # Continue daisy chain
    @app.call(env) 
  end


  def fetch_checkouts (env) 
    url = env[:global_config].cookbook_fetcher.url
    env[:ui].info "Fetching checkout list from #{url}"
    
    checkouts = fetch_checkout_list url
    perform_checkouts checkouts
    update_links checkouts
  end

  def fetch_checkout_list (url)
    require 'open-uri'

    checkouts = { :by_dir => {}, :cookbook_list => [] } 

    open(url, {:ssl_verify_mode => OpenSSL::SSL::VERIFY_NONE }) do |resp|
      resp.each do |line|
        line.chomp!
        if !line.empty? then
          pieces = line.split(/,/)
          branch = pieces[3]
          dir = pieces[2]

          # Build info hash
          checkouts[:by_dir][dir] = {
            :vcs => pieces[0],
            :repo => pieces[1],
            :dir => dir,
            :branch => pieces[3],
            :creds => pieces[4],          
          }
          
          # Build cookbook list.  Use first part of directory, and append cookbooks
          checkouts[:cookbook_list].push 'checkouts/' + (dir.split('/'))[0] + '/cookbooks'

          # Write cookbook order to a file, in case we are later disabled
          File.open('.cookbook-order', 'w') do |f|
            f.print(checkouts[:cookbook_list].join("\n"))
          end

        end
      end
    end

    return checkouts

  end

  def perform_checkouts (checkouts)

    if !Dir.exists?("checkouts") then Dir.mkdir("checkouts") end
    
    Dir.chdir("checkouts") do  
      checkouts[:by_dir].each do |dir, info|
        puts "Updating checkout '#{dir}'"
        if info[:vcs] == 'git' then

          if Dir.exists?(info[:dir]) then
            # pull
            Dir.chdir(info[:dir]) do
              # TODO ignores git creds
              cmd = "git checkout #{info[:branch]}"
              unless system cmd then raise "Could not '#{cmd}'" end
              cmd = "git pull"
              unless system cmd then raise "Could not '#{cmd}'" end
            end
          else
            # clone
            cmd = "git clone -b #{info[:branch]} #{info[:repo]} #{info[:dir]}"
            unless system cmd then raise "Could not '#{cmd}'" end
          end
        else
          raise "Unsupported VCS '#{info[:vcs]}' in checkout list for entry '#{dir}'"
        end
      end
    end
  end

  def update_links (checkouts) 
    things_to_link = ["roles", "nodes", "handlers", "data_bags"]
    puts "Updating links to #{things_to_link.join(', ')}"

    if !Dir.exists?("combined") then Dir.mkdir("combined") end
    Dir.chdir("combined") do  

      # Create/clear the subdirs
      things_to_link.each do |thing|
        if !Dir.exists?(thing) then Dir.mkdir(thing) end
        Dir.foreach(thing) do |file|
          if FileTest.symlink?(file) then File.delete(file) end
        end
      end
    end

    # Being careful to go in cookbook order, symlink the files
    checkouts[:cookbook_list].each do |cookbook_dir|
      checkout_dir = (cookbook_dir.split('/'))[1]
      things_to_link.each do |thing|
        co_thing_dir = "checkouts/#{checkout_dir}/#{thing}"
        combined_dir = "combined/#{thing}"
        if Dir.exists?(co_thing_dir) then
          Dir.entries(co_thing_dir).grep(/\.(rb|json)$/).each do |file|
            # Under vagrant, we see this directory as /vagrant/checkouts/foo/role/bar.rb
            # Use -f so later checkouts can override earlier ones
            cmd = "ln -sf /vagrant/#{co_thing_dir}/#{file} combined/#{thing}/#{file}"
            unless system cmd then raise "Could not '#{cmd}'" end
          end
        end
      end
    end  
  end


end

Vagrant.actions[:provision].insert(Vagrant::Action::General::Validate, CookbookFetcher)
# Note that :up includes :start ( see https://github.com/mitchellh/vagrant/blob/master/lib/vagrant/action/builtin.rb )
Vagrant.actions[:start].insert(Vagrant::Action::General::Validate, CookbookFetcher)


# Injects auto-checkout-derived chef-solo config
class CookbookFetcherConfigureChef 
  def initialize(app, env)
    @app = app
  end

  def call(env)
    # Do this even if fetch is disabled

    require 'pp'
    # there has got to be a better way
    provisioners_list = env[:vm].config.to_hash["keys"][:vm].provisioners 

    chef_solo = provisioners_list.find { |p| p.shortcut === :chef_solo }
    if !chef_solo.nil? then
      solo_cfg = chef_solo.config
      
      if solo_cfg.roles_path.nil? then
        solo_cfg.roles_path = "combined/roles"
      else
        env[:ui].warn "Auto-checkout is keeping your custom chef-solo role path"
      end

      if solo_cfg.data_bags_path.nil? then
        solo_cfg.data_bags_path = "combined/data_bags"
      else
        env[:ui].warn "Auto-checkout is keeping your custom chef-solo data_bags path"
      end

      # Cookbooks has a default
      if solo_cfg.cookbooks_path === ["cookbooks", [:vm, "cookbooks"]] then
        # Read from filesystem
        if !File.exists?(".cookbook-order") then
          env[:ui].error "Auto-checkout could not a .cookbook-order file.  You need to run provision with autocheckout enabled at least once (or else specify your own cookbook path)"
        end

        cbs = []
        IO.readlines(".cookbook-order").each { |line| cbs.push line.chomp }
        solo_cfg.cookbooks_path = cbs
      else
        env[:ui].warn "Auto-checkout is keeping your custom chef-solo cookbook path"
      end

    end

    # Continue daisy chain
    @app.call(env) 
  end
end

Vagrant.actions[:provision].insert(Vagrant::Action::VM::Provision, CookbookFetcherConfigureChef)
Vagrant.actions[:start].insert(Vagrant::Action::VM::Provision, CookbookFetcherConfigureChef)