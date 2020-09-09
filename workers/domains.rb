# domains
require 'yaml/store'
require "ostruct"

host_names = []

domains = YAML::Store.new "../data/domains.store"
paths = Dir.glob("../data/**/settings.store")

paths.each do |path|
  split_path = path.split('/')
  settings_store = YAML::Store.new path

  settings_store.transaction(true) do
    settings_store.roots.each do |data_root_name|
      settings = settings_store[data_root_name]

      slug = settings.slug
      tmp_domain = settings.domain

      if slug and tmp_domain
        p slug, tmp_domain

        if tmp_domain == ''
          next
        end

        # check if subdomain or regular domain and remove www
        if tmp_domain.include? 'www.'
          tmp_domain.slice! 'www.'
          domain = tmp_domain
          type = 'domain'
        elsif tmp_domain.scan(/\./).length >= 2
          domain = tmp_domain
          type = 'subdomain'
        else
          domain = tmp_domain
          type = 'domain'
        end


        domains.transaction do
          domain_obj = OpenStruct.new(domain: domain, slug: slug, type: type)
          domains[slug] = domain_obj
        end
      end

    end
  end

end
