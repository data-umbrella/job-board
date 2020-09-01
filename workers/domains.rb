# domains
require 'yaml/store'
require "ostruct"

host_names = []

accounts = YAML::Store.new "../data/accounts.store"
domains = YAML::Store.new "../data/domains.store"

accounts.transaction(true) do
  accounts.roots.each do |data_root_name|

    account = accounts[data_root_name]
    slug = account.slug
    tmp_domain = account.domain

    if slug and tmp_domain
      p slug, tmp_domain

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
