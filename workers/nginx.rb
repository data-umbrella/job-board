# Must run with root crontab
# https://askubuntu.com/questions/173924/how-to-run-a-cron-job-using-the-sudo-command

require 'yaml/store'
require 'ostruct'
require 'fileutils'

domains = YAML::Store.new "../data/domains.store"
arr = []

domains.transaction(true) do
  domains.roots.each do |data_root_name|
    domain = domains[data_root_name]
    arr.append(domain)
  end
end

p "list of all domains: #{arr}"

# Check list of existing domains
current_hosts = Dir.chdir("/etc/nginx/sites-available") { Dir.glob('*') }
p "list of server blocks: #{current_hosts}"

# Loop through all domains in database
arr.each do |account|
  domain = account.domain
  p "checking #{domain}"

  # check if already has virtual host, then skip
  if current_hosts.include? domain
    p "#{domain} already exists"
    next
  end

  # check if subdomain or domain
  if account.type == "subdomain"
    p "found new subdomain: #{domain}"

    # Go to nginx folder
    Dir.chdir("/etc/nginx/sites-available") do

      # duplicate subdomain template
      FileUtils.cp("#{Dir.pwd}/subdomain", "#{Dir.pwd}/#{domain}")

      # replace domain placeholder with actual domain name
      file_name = "#{Dir.pwd}/#{domain}"
      text = File.read(file_name)
      new_contents = text.gsub(/google.com/, domain)
      File.open(file_name, "w") { |file| file.puts new_contents }

      # Create symlink to sites-enabled (shell)
      system("sudo ln -s /etc/nginx/sites-available/#{domain} /etc/nginx/sites-enabled/")

      # Restart NGINX (shell)
      system("sudo systemctl restart nginx")

      # Get SSL cert and force redirect
      system("sudo certbot --nginx --agree-tos --redirect --keep -d #{domain} --email me@tyshaikh.com")

      # Restart NGINX (shell)
      system("sudo systemctl restart nginx")

    end

  elsif account.type = "domain"
    p "found new domain", domain

    # Go to nginx folder
    Dir.chdir("/etc/nginx/sites-available") do

      # duplicate domain template
      FileUtils.cp("#{Dir.pwd}/domain", "#{Dir.pwd}/#{domain}")

      # replace domain placeholder with actual domain name
      file_name = "#{Dir.pwd}/#{domain}"
      text = File.read(file_name)
      new_contents = text.gsub(/google.com/, domain)
      File.open(file_name, "w") { |file| file.puts new_contents }

      # Create symlink to sites-enabled (shell)
      system("sudo ln -s /etc/nginx/sites-available/#{domain} /etc/nginx/sites-enabled/")

      # Get SSL cert for both root and www, force redirect
      system("sudo certbot --nginx --agree-tos --redirect --keep -d #{domain} -d www.#{domain} --email me@tyshaikh.com")

      # Restart NGINX (shell)
      system("sudo systemctl restart nginx")

    end

  else
    next
  end

end
