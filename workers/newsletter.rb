require 'time'
require 'yaml/store'
require 'ostruct'
require 'mailgun-ruby'

paths = Dir.glob("../data/**/newsletter.store")

paths.each do |path|
  split_path = path.split('/')
  slug = split_path[2]
  email_list = []

  # Check if newsletter is empty
  count = 0

  newsletter_store = YAML::Store.new path
  newsletter_store.transaction(true) do  # begin read-only transaction, no changes allowed
    newsletter_store.roots.each do |data_root_name|
      count += 1
      subscriber = newsletter_store[data_root_name]
      email_list.append(subscriber.email)
    end
  end

  p "#{slug} has #{count} subscribers"
  p "list #{email_list}"

  next if count == 0

  # Pull out all the jobs listed in the last 7 days
  jobs_store = YAML::Store.new "../data/#{slug}/jobs.store"
  new_jobs = []
  today = Time.now

  jobs_store.transaction(true) do  # begin read-only transaction, no changes allowed
    jobs_store.roots.each do |data_root_name|
      jobs_listing = jobs_store[data_root_name]

      # Find difference in days
      job_date = Time.parse(jobs_listing.date)
      diff = ((today - job_date) / 86400).round

      if diff < 7
        new_jobs.append(jobs_listing)
      end
    end
  end

  settings_store = YAML::Store.new "../data/#{slug}/settings.store"
  settings = settings_store.transaction { settings_store.fetch(slug, false) }

  intro_body = "<p>These jobs were posted last week on #{settings.org_name}<p>"
  job_markup = ''

  # Create domain variable, based on if custom domain setup or not
  if (settings.domain) and (!settings.domain.empty?)
    domain_route = "http://#{settings.domain}"
  else
    domain_route = "http://tryferret.com/board/#{slug}"
  end

  new_jobs.each do |job|
    markup = "<p><a href='#{domain_route}/jobs/#{job.slug}' target='_blank'>#{job.position} - #{job.company_name} - #{job.location}</a><p>"
    job_markup += markup
  end

  email_body = intro_body + job_markup

  # Figure out unsubscribe (unique key to post/delete route?)
  # Remove me from this newsletter (post route to remove from pstore) (POST and confirmation page)

  # Send batch email to all recipients

  # First, instantiate the Mailgun Client with your API key
  mg_client = Mailgun::Client.new "key-0916b0e78ee39f94534d56475d32b015"
  mb_obj = Mailgun::BatchMessage.new mg_client, "mg.tryferret.com"

  # Define the from address
  mb_obj.from "support@tryferret.com", {"first" => settings.org_name}

  # Define the subject.
  mb_obj.subject "Weekly job postings from #{settings.org_name}!"

  # Define the body of the message.
  mb_obj.body_html email_body

  # Loop through all of your recipients
  email_list.each do |email|
    mb_obj.add_recipient(:to, email, {})
    p "Email sent to #{email}"
  end

  mb_obj.finalize

end
