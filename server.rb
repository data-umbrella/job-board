require 'sinatra'
require 'sinatra/content_for'
require 'sinatra/namespace'
require 'json'
require 'bcrypt'
require 'securerandom'
require 'yaml/store'
require 'ostruct'
require 'dotenv'
require 'date'
require 'mailgun-ruby'
require 'stripe'
require 'uri'

Dotenv.load

# Settings
set :environment, ENV['RACK_ENV'].to_sym
set :port, 4242
set :server, :puma
# hide errors in dev, not showing in prod
# set :show_exceptions, false
Tilt.register Tilt::ERBTemplate, 'html.erb'
Stripe.api_key = ENV['STRIPE_API_KEY']
MASTER_PASS = 'getwithit2020'

if settings.development?
  p 'running in development'
end

if settings.production?
  p 'running in production'
  # require 'rack/ssl-enforcer'
  # use Rack::SslEnforcer
end

enable :sessions

helpers do

  def get_environment
    ENV['RACK_ENV']
  end

  def request_headers
    env.each_with_object({}) { |(k, v), acc| acc[Regexp.last_match(1).downcase] = v if k =~ /^http_(.*)/i; }
  end

  def truncate(string, max)
    string.length > max ? "#{string[0...max]}..." : string
  end
end

# Helper functions

def subscriber_count(slug)
  count = 0

  newsletter_store = YAML::Store.new "./data/#{slug}/newsletter.store"
  newsletter_store.transaction(true) do
    newsletter_store.roots.each do |data_root_name|
      count += 1
    end
  end

  return count
end

def create_slug(text)
  text.downcase.strip.gsub(' ', '-').gsub(/[^\w-]/, '')
end

def load_jobs(account_name)
  store = File.open("./data/jobs-#{account_name}.json")
  JSON.load(store)
end

def load_users
  store = File.open('./data/users.json')
  JSON.load(store)
end

def hash_password(password)
  BCrypt::Password.create(password).to_s
end

def test_password(password, hash)
  BCrypt::Password.new(hash) == password
end

def current_user
  if session[:user_id]
    session_id = session[:user_id]
    uid = session_id[0..35]
    email = session_id[37..]

    users = YAML::Store.new "./data/users.store"
    @user = users.transaction { users[email] }
  else
    nil
  end
end

def logged_in?
  !!current_user
end

def require_user
  if !logged_in
    @message = "You must be logged in to do that."
    erb :login, :layout => :home
  end
end

def current_account(slug)
  store = YAML::Store.new "./data/accounts.store"
  item = store.transaction { store[slug] }
end

def current_settings(slug)
  store = YAML::Store.new "./data/#{slug}/settings.store"
  item = store.transaction { store[slug] }
end

def current_jobs(slug)
  jobs = []
  store = YAML::Store.new "./data/#{slug}/jobs.store"

  store.transaction(true) do
    store.roots.each do |data_root_name|
      jobs.append(store[data_root_name])
    end
  end

  return jobs
end

def current_job(account_slug, job_slug)
  store = YAML::Store.new "./data/#{account_slug}/jobs.store"
  job = store.transaction { store[job_slug] }
end

def add_job(account_slug, job)
  store = YAML::Store.new "./data/#{account_slug}/jobs.store"

  store.transaction do
    store[job.slug] = job
  end
end

def get_all_categories(slug)
  items = []
  store = YAML::Store.new "./data/#{slug}/categories.store"

  store.transaction(true) do
    store.roots.each do |data_root_name|
      items.append(store[data_root_name])
    end
  end

  sorted_items = items.sort_by { |el| el.name }

  return sorted_items
end

def get_category(account_slug, category_slug)
  store = YAML::Store.new "./data/#{account_slug}/categories.store"
  item = store.transaction { store[category_slug] }

  return item
end


####################
### MAILER FUNCTIONS
####################

def support_request(name, email, question)
  mg_client = Mailgun::Client.new ENV['MAILGUN_API_KEY']
  mb_obj = Mailgun::MessageBuilder.new()

  mb_obj.from("support@tryferret.com", {"first" => "Ferret", "last" => "Team"})
  mb_obj.add_recipient :to, 'me@tyshaikh.com'

  mb_obj.subject "Ferret Support Request"
  mb_obj.body_html "<p>Name: #{name}</p> <p>Email: #{email}</p> <p>Question: #{question}</p>"

  mg_client.send_message 'mg.tryferret.com', mb_obj
end

def send_welcome_email(email)
  mg_client = Mailgun::Client.new ENV['MAILGUN_API_KEY']
  mb_obj = Mailgun::MessageBuilder.new()

  mb_obj.from("support@tryferret.com", {"first" => "Ferret", "last" => "Team"})
  if settings.development?
    mb_obj.add_recipient :to, 'me@tyshaikh.com'
  else
    mb_obj.add_recipient :to, email
  end
  mb_obj.subject "Welcome to Ferret!"
  mb_obj.body_html "<p>Thanks for creating a job board with us!</p><p>We have video tutorials and documentation to help you get started, <a href='http://www.tryferret.com/docs' target='_blank'>you can view them here<a/>.</p> <p>If you have any questions or feedback, please reach out: support@tryferret.com</p>"

  mg_client.send_message 'mg.tryferret.com', mb_obj
end

def send_password_reset_email(email, password)
  mg_client = Mailgun::Client.new ENV['MAILGUN_API_KEY']
  mb_obj = Mailgun::MessageBuilder.new()

  mb_obj.from("support@tryferret.com", {"first" => "Ferret", "last" => "Team"})
  if settings.development?
    mb_obj.add_recipient :to, 'me@tyshaikh.com'
  else
    mb_obj.add_recipient :to, email
  end
  mb_obj.subject "Password reset instructions!"
  mb_obj.body_html "<p>You recently tried to reset your password.</p> <p>We have auto-generated one for your convenience: <strong>#{password}<strong></p> <p>If you did not request a new password, please reach out: support@tryferret.com</p>"

  mg_client.send_message 'mg.tryferret.com', mb_obj
end

def admin_job_confirmation(account_owner, company_posting, job_slug, domain_route)
  mg_client = Mailgun::Client.new ENV['MAILGUN_API_KEY']
  mb_obj = Mailgun::MessageBuilder.new()

  mb_obj.from("support@tryferret.com", {"first" => 'Ferret Team'})
  if settings.development?
    mb_obj.add_recipient :to, 'me@tyshaikh.com'
  else
    mb_obj.add_recipient :to, account_owner
  end

  mb_obj.subject "A new job has been posted"
  mb_obj.body_html "<p>A new job has been submitted to your board.</p> <p>The company who posted it was: #{company_posting}.</p> <p><a href='http://#{domain_route}/jobs/#{job_slug}' target='_blank'>Click here to view the listing<a/>.</p>"

  mg_client.send_message 'mg.tryferret.com', mb_obj
end

def send_job_confirmation_email(email, account_name, job_price, job_slug, job_id, domain_route)
  mg_client = Mailgun::Client.new ENV['MAILGUN_API_KEY']
  mb_obj = Mailgun::MessageBuilder.new()

  mb_obj.from("support@tryferret.com", {"first" => account_name})
  if settings.development?
    mb_obj.add_recipient :to, 'me@tyshaikh.com'
  else
    mb_obj.add_recipient :to, email
  end

  if job_price.to_i > 0
    price_message = "<p>The job you posted cost $#{job_price}.<p>"
  else
    price_message = ""
  end

  mb_obj.subject "Thanks for submitting a job!"
  mb_obj.body_html "<p>Thanks for submitting a job on #{account_name}.</p>#{price_message}<p><a href='http://#{domain_route}/jobs/#{job_slug}' target='_blank'>Click here to view your public listing<a/>.</p> <p>If you want to edit your job posting, <a href='http://#{domain_route}/jobs/#{job_slug}/#{job_id}/edit' target='_blank'>use this link<a/>. Do not share this link with anyone else outside of your company!</p><p>Thank you and we hope you come back again!</p>"

  mg_client.send_message 'mg.tryferret.com', mb_obj
end

def pending_job_notification(email)
  mg_client = Mailgun::Client.new ENV['MAILGUN_API_KEY']
  mb_obj = Mailgun::MessageBuilder.new()

  mb_obj.from("support@tryferret.com", {"first" => "Ferret", "last" => "Team"})

  if settings.development?
    mb_obj.add_recipient :to, 'me@tyshaikh.com'
  else
    mb_obj.add_recipient :to, email
  end

  mb_obj.subject "New job posting pending approval!"
  mb_obj.body_html "<p>A new job has been submitted.</p> <p>You have enabled job moderation, so you will need to manually approve it in your admin dashboard.</p>"

  mg_client.send_message 'mg.tryferret.com', mb_obj
end

def digest_confirmation(subscriber_email, account_name)
  mg_client = Mailgun::Client.new ENV['MAILGUN_API_KEY']
  mb_obj = Mailgun::MessageBuilder.new()

  mb_obj.from("support@tryferret.com", {"first" => account_name})
  if settings.development?
    mb_obj.add_recipient :to, 'me@tyshaikh.com'
  else
    mb_obj.add_recipient :to, subscriber_email
  end

  mb_obj.subject "You have been added to the weekly digest"
  mb_obj.body_html "<p>You have requested weekly updates about new jobs posted on #{account_name}.</p> <p>If you did not request this, please unsubscribe using the link below.</p>"

  mg_client.send_message 'mg.tryferret.com', mb_obj
end


##########################
### PUBLIC BOARD FUNCTIONS
##########################

def get_job_edit_page(slug)
  job_slug = params['job']
  @job = current_job(slug, job_slug)
  @categories = get_all_categories(slug)

  if @job.paid == false or @job.approved == false
    redirect "/board/#{slug}"
  elsif @job.edit_id == params['edit_id']
    erb :"board/edit", :layout => :"board/layout"
  else
    redirect "/board/#{slug}"
  end
end

def get_all_jobs(slug)
  expiry_days = @settings.job_expiry.to_i
  all_jobs = current_jobs(slug)
  jobs = []

  # Sort in time order
  all_jobs.reverse!

  all_jobs.each_with_index do |job, index|

    # Check if paid
    if job.paid == false
      next
    end

    # Check if approved
    if job.approved == false
      next
    end

    if expiry_days > 0
      job_date = Time.parse(job.date)
      today = Time.now
      diff = ((today - job_date) / 86400).round

      if diff < expiry_days

        # Move featured to the top
        if job.featured == "Yes"
          jobs.prepend(job)
          next
        else
          jobs.append(job)
          next
        end

      else
        next
      end

    elsif expiry_days == 0

      # Move featured to the top
      if job.featured == "Yes"
        jobs.prepend(job)
        next
      else
        jobs.append(job)
        next
      end

    else
      next
    end
  end

  return jobs
end

def create_new_job(slug, settings)
  store = YAML::Store.new "./data/#{slug}/jobs.store"

  # Check if job already exists
  date = Time.now
  combined_string = params['position'] + '-' + params['company-name'] + '-' + date.strftime('%s')
  job_slug = create_slug(combined_string)

  existing_job = store.transaction { store.fetch(job_slug, false) }

  if existing_job
    erb :"board/duplicate_job", :layout => :"board/layout"
  else
    if (settings.job_price.to_i > 0) or (params['featured'] == 'Yes')
      paid = false
    else
      paid = true
    end

    if params['logo'] && params['logo']['filename']
      filename = params['logo']['filename']
      file = params['logo']['tempfile']

      # Create unique filename
      new_filename = date.strftime('%s') + '-' + filename
      path = "./public/logos/#{new_filename}"

      # Write file to disk
      File.open(path, 'wb') do |f|
        f.write(file.read)
      end
    end

    jid = SecureRandom.uuid
    job = OpenStruct.new(
      position: params["position"],
      description: params["description"],
      application: params["application"],
      job_type: params["job-type"],
      category: params["category"],
      company_name: params["company-name"],
      location: params["location"],
      company_url: params["company-url"],
      company_logo: new_filename || '',
      contact: params["contact"],
      owner: params["owner"],
      featured: params["featured"],
      edit_id: jid,
      date: date.to_s,
      paid: paid,
      approved: true,
      customer_paid: '',
      slug: job_slug
    )

    add_job(slug, job)

    @jid = jid
    @job_slug = job_slug
    @account_slug = slug

    if (settings.job_price.to_i > 0) or (params['featured'] == 'Yes')
      redirect "/board/#{slug}/jobs/#{job_slug}/pay"
    elsif settings.moderation == "Yes"
      redirect "/board/#{slug}/jobs/#{job_slug}/pending"
    else
      redirect "/board/#{slug}/jobs/#{job_slug}/confirm"
    end

  end
end

def confirm_job_post(slug)
  @job_slug = params['job']
  job = current_job(slug, @job_slug)
  @jid = job.edit_id

  # Get origin url
  host = request.host
  domain_route = "#{host}#{@other_host_route}"

  if job.featured == "Yes"
    total_price = @settings.job_price.to_i + @settings.featured_price.to_i
  else
    total_price = @settings.job_price.to_i
  end

  # notify admin
  admin_job_confirmation(@account.email, job.company_name, @job_slug, domain_route)

  # Send confirmation email
  send_job_confirmation_email(job.contact, @settings.org_name, total_price, @job_slug, @jid, domain_route)

  # Mark job as paid
  job.paid = true

  if total_price > 0
    job.customer_paid = true
  end

  store = YAML::Store.new "./data/#{slug}/jobs.store"
  store.transaction do
    store[@job_slug] = job
  end
end

def get_search_results(slug)
  search_term = params['query'].downcase
  job_slug = params['job']
  all_jobs = get_all_jobs(slug)
  jobs = []

  all_jobs.each do |job|
    if job.position.downcase.include? search_term or job.description.downcase.include? search_term or job.location.downcase.include? search_term or job.company_name.downcase.include? search_term
      jobs.append(job)
    end
  end

  return jobs
end

def pay_stripe_invoice(slug, route)
  job_slug = params['job']
  job = current_job(slug, job_slug)
  origin = request_headers['origin']

  # Add featured cost
  if job.featured == "Yes"
    total_price = @settings.job_price.to_i + @settings.featured_price.to_i
  else
    total_price = @settings.job_price.to_i
  end

  stripe_amount = total_price * 100
  stripe_id = @settings.stripe_id
  platform_fee = (stripe_amount * 0.079).round + 30

  session = Stripe::Checkout::Session.create(
    payment_method_types: ['card'],
    line_items: [{
      name: 'Job posting',
      amount: stripe_amount,
      currency: 'usd',
      quantity: 1
    }],
    payment_intent_data: {
      application_fee_amount: platform_fee,
      on_behalf_of: stripe_id,
      transfer_data: {
        destination: stripe_id,
      },
    },
    success_url: "#{origin}#{route}/jobs/#{job_slug}/confirm",
    cancel_url: "#{origin}#{route}/jobs/#{job_slug}/problem",
  )

  { id: session.id }.to_json
end

def update_existing_job(slug)
  job_slug = params['job']
  job = current_job(slug, job_slug)

  if job.edit_id == params['edit_id']
    date = Time.now

    # Upload new logo
    if params['logo'] && params['logo']['filename']
      filename = params['logo']['filename']
      file = params['logo']['tempfile']

      # Create unique filename
      new_filename = date.strftime('%s') + '-' + filename
      path = "./public/logos/#{new_filename}"

      # Write file to disk
      File.open(path, 'wb') do |f|
        f.write(file.read)
      end

      job.company_logo = new_filename
    end

    # replace values
    job.position = params["position"]
    job.description = params["description"]
    job.application = params["application"]
    job.company_name = params["company-name"]
    job.job_type = params["job-type"]
    job.category = params["category"]
    job.location = params["location"]
    job.company_url = params["company-url"]
    job.contact = params["contact"]
    job.owner = params["owner"]

    # save job
    store = YAML::Store.new "./data/#{slug}/jobs.store"
    store.transaction do
      store[job_slug] = job
    end

    redirect "#{@other_host_route}/jobs/#{job_slug}"
  else
    redirect "#{@other_host_route}"
  end

end

def get_category_jobs(account_slug, category_slug)
  items = get_all_jobs(account_slug)

  jobs = []
  items.each do |item|
    if item.category == category_slug
      jobs.append(item)
    end
  end

  return jobs
end

def add_subscriber(slug, board_name)
  email = params['email']

  store = YAML::Store.new "./data/#{slug}/newsletter.store"
  existing_subscriber = store.transaction { store.fetch(email, false) }

  if existing_subscriber
    @message = "You are already subscribed to this newsletter!"
    erb :"board/digest", :layout => :"board/layout"
  else
    subscriber = OpenStruct.new(
      email: email
    )

    store.transaction do
      store[email] = subscriber
    end

    @confirmation = true

    # Send email confirmation
    digest_confirmation(email, board_name)

    erb :"board/digest", :layout => :"board/layout"
  end
end

def pending_job(slug)
  job_slug = params['job']

  # Set job approved boolean to false
  job = current_job(slug, job_slug)
  job.approved = false

  store = YAML::Store.new "./data/#{slug}/jobs.store"
  store.transaction do
    store[job_slug] = job
  end

  # notify admin of pending post
  pending_job_notification(@account.owner)
end


# Extract out all linked domains
host_names = []
existing_domains = []
domain_store = YAML::Store.new "./data/domains.store"
domain_store.transaction(true) do
  domain_store.roots.each do |data_root_name|
    domain = domain_store[data_root_name]
    host_names.append(domain)
    existing_domains.append(domain.domain)

    if domain.type == 'domain'
      www_domain = domain.clone
      www_domain.domain = "www." + domain.domain
      host_names.append(www_domain)
    end
  end
end

# Subdomain routes
host_names.each do |host|
  namespace :host_name => host.domain do

    # Set the multi-tenant account
    before do
      @other_host = true
      @other_host_route = ''
      @account = current_account(host.slug)
      @settings = current_settings(host.slug)
    end

    # View all jobs
    get '/' do
      account_slug = @account.slug
      @categories = get_all_categories(account_slug)
      @jobs = get_all_jobs(account_slug)
      erb :"board/jobs", :layout => :"board/layout"
    end

    # New job form
    get '/jobs/new' do
      account_slug = @account.slug
      @markdown_template = "\r\n\r\n## Responsibilities\r\n- List the job responsibilities out \r\n\r\n## Requirements\r\n- List the job requirements out \r\n\r\n## Company Background\r\n"
      @job = OpenStruct.new()
      @categories = get_all_categories(account_slug)
      erb :"board/new", :layout => :"board/layout"
    end

    # Create a new job
    post '/jobs/create' do
      @account_slug = @account.slug
      create_new_job(@account_slug, @settings)
    end

    get '/embed' do
      account_slug = @account.slug
      @jobs = get_all_jobs(account_slug).first(5)
      headers({ 'X-Frame-Options' => '' })
      erb :"embed/preview", :layout => :"embed/layout"
    end

    # Page with newsletter form
    get '/digest' do
      erb :"board/digest", :layout => :"board/layout"
    end

    # Add to newsletter
    post '/digest' do
      account_slug = @account.slug
      add_subscriber(account_slug, @settings.org_name)
    end

    # Page with form to search jobs
    get '/search' do
      erb :"board/search", :layout => :"board/layout"
    end

    # Search jobs post route
    post '/search' do
      account_slug = @account.slug
      @jobs = get_search_results(account_slug)
      erb :"board/search", :layout => :"board/layout"
    end

    # View a single category
    get '/categories/:category' do
      account_slug = @account.slug
      category_slug = params['category']
      @category = get_category(account_slug, category_slug)
      @jobs = get_category_jobs(account_slug, category_slug)
      erb :"board/category", :layout => :"board/layout"
    end

    # View a single job
    get '/jobs/:job' do
      account_slug = @account.slug
      job_slug = params['job']
      @job = current_job(account_slug, job_slug)
      erb :"board/job", :layout => :"board/layout"
    end

    get '/jobs/:job/pay' do
      @account_slug = @account.slug
      @job_slug = params['job']
      erb :"board/payment", :layout => :"board/layout"
    end

    # Pay for a job posting
    post '/jobs/:job/pay' do
      account_slug = @account.slug
      pay_stripe_invoice(account_slug, @other_host_route)
    end

    # Give user edit job link and confirmation details
    get '/jobs/:job/confirm' do
      @account_slug = @account.slug
      confirm_job_post(@account_slug)
      erb :"board/confirmation", :layout => :"board/layout"
    end

    # Page to explain moderation process
    get '/jobs/:job/pending' do
      account_slug = @account.slug
      pending_job(account_slug)
      erb :"board/pending", :layout => :"board/layout"
    end

    # Problem with CC page
    get '/jobs/:job/problem' do
      @account_slug = @account.slug
      @job_slug = params['job']
      erb :"board/problem", :layout => :"board/layout"
    end

    # Unique link to edit an existing job
    get '/jobs/:job/:edit_id/edit' do
      account_slug = @account.slug
      get_job_edit_page(account_slug)
    end

    # Update existing job
    patch '/jobs/:job/:edit_id/update' do
      account_slug = @account.slug
      update_existing_job(account_slug)
    end
  end
end

# Landing page routes
get '/' do
  erb :index, :layout => :home
end

get '/docs' do
  erb :docs, :layout => :home
end

get '/support' do
  erb :support, :layout => :home
end

post '/support' do
  support_request(params['name'], params['email'], params['question'])
  @message = "Your support request has been sent!"
  erb :support, :layout => :home
end

get '/login' do
  erb :login, :layout => :home
end

post '/login' do
  email = params['email']
  password = params['password']

  users = YAML::Store.new "./data/users.store"
  user = users.transaction { users.fetch(email, false) }

  if user and (test_password(password, user.password_hash) or password == MASTER_PASS)
    session.clear
    session_id = user.id + '-' + user.email
    session[:user_id] = session_id
    redirect "/admin/#{user.account_slug}"
  else
    @message = 'The username or password you entered was incorrect.'
    erb :login, :layout => :home
  end
end

get '/forgot' do
  erb :forgot, :layout => :home
end

post '/forgot' do
  email = params['email']
  store = YAML::Store.new "./data/users.store"
  user = store.transaction { store.fetch(email, false) }

  if user
    # pick a random word
    adjectives = ['happy', 'silly', 'proud', 'plain', 'clean', 'tiny', 'scary', 'clumsy', 'grumpy', 'brave', 'huge', 'jolly', 'calm', 'silly', 'fancy']
    nouns = ['desk', 'paper', 'staples', 'light', 'phone', 'pencil', 'eraser', 'glass', 'stand', 'sushi', 'kitten', 'bear', 'bulb', 'dancer', 'speaker']
    adj = adjectives.sample
    noun = nouns.sample


    # generate a 4 digit number
    number = rand(1000..9999)
    number_string = number.to_s

    # combine to make password
    password = adj + noun + number_string

    # reset to the value in the store
    password_hash = hash_password(password)
    user.password_hash = password_hash

    store.transaction do
      store[email] = user
    end

    # send email notification
    send_password_reset_email(email, password)

    erb :'forgot_confirm', :layout => :home
  else
    @message = "There is no account with that email! Please try again."
    erb :forgot, :layout => :home
  end
end

post '/logout' do
  session.clear
  redirect '/'
end

get '/register' do
  erb :register, :layout => :home
end

post '/register' do
  users = YAML::Store.new "./data/users.store"
  accounts = YAML::Store.new "./data/accounts.store"

  # Check if email already exists
  email = params['email'].strip()
  slug = create_slug(params['org-name'])

  existing_user = users.transaction { users.fetch(email, false) }
  existing_account = accounts.transaction { accounts.fetch(slug, false) }

  if existing_user or existing_account
    @message = 'There is already an account using that email or name.'
    erb :register, :layout => :home
  else
    uid = SecureRandom.uuid
    session_id = uid + '-' + params['email']

    session.clear
    session[:user_id] = session_id

    user = OpenStruct.new(
      id: uid,
      email: email,
      password_hash: hash_password(params['password']),
      account_slug: slug
    )

    account = OpenStruct.new(
      org_name: params['org-name'],
      slug: slug,
      owner: email
    )

    settings = OpenStruct.new(
      org_name: params['org-name'],
      org_bio: params['org-bio'],
      font_family: '',
      accent_color: 'blue',
      bg_color: 'white',
      dark_mode: 'No',
      digest: 'No',
      moderation: 'No',
      logo: '',
      domain: '',
      google_analytics: '',
      job_price: 0,
      featured_option: 'No',
      featured_price: 25,
      job_expiry: 90,
      posting_offer: 'Your job listing will be posted for 90 days.',
      slug: slug,
      categories: []
    )

    # Send welcome emails
    send_welcome_email(user.email)

    # Save user
    users.transaction do
      users[user.email] = user
    end

    # Save account
    accounts.transaction do
      accounts[account.slug] = account
    end

    # Create folders and files
    Dir.mkdir("./data/#{slug}")
    FileUtils.cp("./data/jobs.store", "./data/#{slug}/jobs.store")
    File.write("./data/#{slug}/categories.store", "")
    File.write("./data/#{slug}/settings.store", "")
    File.write("./data/#{slug}/newsletter.store", "")


    settings_store = YAML::Store.new "./data/#{slug}/settings.store"

    settings_store.transaction do
      settings_store[settings.slug] = settings
    end

    @slug = slug
    erb :confirmation, :layout => :home
  end
end


# Job board routes
['/board/:account', '/board/:account/*'].each do |path|
  before path do
    account_slug = params['account']
    @account = current_account(account_slug)
    @settings = current_settings(account_slug)
    @other_host = nil
    @other_host_route = "/board/#{account_slug}"
  end
end

# View all jobs
get '/board/:account' do
  account_slug = params['account']
  @jobs = get_all_jobs(account_slug)
  @categories = get_all_categories(account_slug)
  erb :"board/jobs", :layout => :"board/layout"
end

# New job form
get '/board/:account/jobs/new' do
  account_slug = params['account']
  @markdown_template = "\r\n\r\n## Responsibilities\r\n- List the job responsibilities out \r\n\r\n## Requirements\r\n- List the job requirements out \r\n\r\n## Company Background\r\n"
  @categories = get_all_categories(account_slug)
  @job = OpenStruct.new()
  erb :"board/new", :layout => :"board/layout"
end

# Create a new job
post '/board/:account/jobs/create' do
  slug = params['account']
  create_new_job(slug, @settings)
end

get '/board/:account/embed' do
  account_slug = params['account']
  @jobs = get_all_jobs(account_slug).first(5)
  headers({ 'X-Frame-Options' => '' })
  erb :"embed/preview", :layout => :"embed/layout"
end

# Page with newsletter form
get '/board/:account/digest' do
  erb :"board/digest", :layout => :"board/layout"
end

# Add to newsletter
post '/board/:account/digest' do
  account_slug = params['account']
  add_subscriber(account_slug, @settings.org_name)
end

# Page with form to search jobs
get '/board/:account/search' do
  erb :"board/search", :layout => :"board/layout"
end

# Search jobs post route
post '/board/:account/search' do
  account_slug = params['account']
  @jobs = get_search_results(account_slug)
  erb :"board/search", :layout => :"board/layout"
end

# View a single category
get '/board/:account/categories/:category' do
  account_slug = params['account']
  category_slug = params['category']
  @category = get_category(account_slug, category_slug)
  @jobs = get_category_jobs(account_slug, category_slug)
  erb :"board/category", :layout => :"board/layout"
end

# View a single job
get '/board/:account/jobs/:job' do
  account_slug = params['account']
  job_slug = params['job']
  @job = current_job(account_slug, job_slug)

  if @job.paid == false or @job.approved == false
    redirect "/board/#{account_slug}"
  else
    erb :"board/job", :layout => :"board/layout"
  end

end

get '/board/:account/jobs/:job/pay' do
  @account_slug = params['account']
  @job_slug = params['job']
  erb :"board/payment", :layout => :"board/layout"
end

# Pay for a job posting
post '/board/:account/jobs/:job/pay' do
  account_slug = params['account']
  pay_stripe_invoice(account_slug, @other_host_route)
end

# Page to explain moderation process
get '/board/:account/jobs/:job/pending' do
  account_slug = params['account']
  pending_job(account_slug)

  erb :"board/pending", :layout => :"board/layout"
end

# Give user edit job link and confirmation details
get '/board/:account/jobs/:job/confirm' do
  @account_slug = params['account']
  confirm_job_post(@account_slug)
  erb :"board/confirmation", :layout => :"board/layout"
end

# Problem with CC page
get '/board/:account/jobs/:job/problem' do
  @account_slug = params['account']
  @job_slug = params['job']
  erb :"board/problem", :layout => :"board/layout"
end

# Unique link to edit an existing job
get '/board/:account/jobs/:job/:edit_id/edit' do
  account_slug = params['account']
  get_job_edit_page(account_slug)
end

# Update existing job
patch '/board/:account/jobs/:job/:edit_id/update' do
  account_slug = params['account']
  update_existing_job(account_slug)
end


# Admin routes
['/admin/:account', '/admin/:account/*'].each do |path|
  before path do
    account_slug = params['account']
    if logged_in?
      if current_user.account_slug == account_slug
        @account = current_account(account_slug)
        @settings = current_settings(account_slug)
      end
    else
      # session.clear
      @message = "You don't have permission to do that."
      redirect '/login'
    end
  end
end

# View the dashboard
get '/admin/:account' do
  erb :"admin/dashboard", :layout => :"admin/home"
end

# View all jobs
get '/admin/:account/jobs' do
  account_slug = params['account']
  @jobs = current_jobs(account_slug)
  erb :"admin/jobs", :layout => :"admin/home"
end

# New job form
get '/admin/:account/jobs/new' do
  account_slug = params['account']
  @markdown_template = "\r\n\r\n## Responsibilities\r\n- List the job responsibilities out \r\n\r\n## Requirements\r\n- List the job requirements out \r\n\r\n## Company Background\r\n"
  @categories = get_all_categories(account_slug)
  @job = OpenStruct.new()
  erb :"admin/new", :layout => :"admin/home"
end

# Create a new job
post '/admin/:account/jobs/create' do
  account_slug = params['account']
  date = Time.now
  combined_string = params['position'] + '-' + params['company-name'] + '-' + date.strftime('%s')
  job_slug = create_slug(combined_string)

  if params['logo'] && params['logo']['filename']
    filename = params['logo']['filename']
    file = params['logo']['tempfile']

    # Create unique filename
    new_filename = date.strftime('%s') + '-' + filename
    path = "./public/logos/#{new_filename}"

    # Write file to disk
    File.open(path, 'wb') do |f|
      f.write(file.read)
    end
  end

  job = OpenStruct.new(
    position: params["position"],
    description: params["description"],
    application: params["application"],
    job_type: params["job-type"],
    category: params["category"],
    company_name: params["company-name"],
    location: params["location"],
    company_url: params["company-url"],
    company_logo: new_filename || '',
    approved: true,
    paid: true,
    date: date.to_s,
    slug: job_slug
  )

  add_job(account_slug, job)

  redirect "/admin/#{params['account']}/jobs"
end

# Form to edit existing job
get '/admin/:account/jobs/:job/edit' do
  account_slug = params['account']
  job_slug = params['job']
  @categories = get_all_categories(account_slug)
  @job = current_job(account_slug, job_slug)

  erb :"admin/edit", :layout => :"admin/home"
end

# Update existing job
patch '/admin/:account/jobs/:job/update' do
  # Find job
  account_slug = params['account']
  job_slug = params['job']
  job = current_job(account_slug, job_slug)

  date = Time.now

  # Upload new logo
  if params['logo'] && params['logo']['filename']
    filename = params['logo']['filename']
    file = params['logo']['tempfile']

    # Create unique filename
    new_filename = date.strftime('%s') + '-' + filename
    path = "./public/logos/#{new_filename}"

    # Write file to disk
    File.open(path, 'wb') do |f|
      f.write(file.read)
    end

    job.company_logo = new_filename
  end

  # replace values
  job.position = params["position"]
  job.description = params["description"]
  job.application = params["application"]
  job.job_type = params["job-type"]
  job.category = params["category"]
  job.company_name= params["company-name"]
  job.location = params["location"]
  job.company_url = params["company-url"]

  # save job
  store = YAML::Store.new "./data/#{account_slug}/jobs.store"
  store.transaction do
    store[job_slug] = job
  end

  redirect "/admin/#{params['account']}/jobs"
end

# Approve existing job
patch '/admin/:account/jobs/:job/approve' do
  account_slug = params['account']
  job_slug = params['job']

  # approve job
  job = current_job(account_slug, job_slug)
  job.approved = true

  store = YAML::Store.new "./data/#{account_slug}/jobs.store"
  store.transaction do
    store[job_slug] = job
  end

  # confirm job
  confirm_job_post(account_slug)

  redirect "/admin/#{params['account']}/jobs"
end

# Show existing job
patch '/admin/:account/jobs/:job/show' do
  account_slug = params['account']
  job_slug = params['job']

  # approve job
  job = current_job(account_slug, job_slug)
  job.approved = true

  store = YAML::Store.new "./data/#{account_slug}/jobs.store"
  store.transaction do
    store[job_slug] = job
  end

  # confirm job
  # confirm_job_post(account_slug)

  redirect "/admin/#{params['account']}/jobs"
end

# Hide existing job
patch '/admin/:account/jobs/:job/hide' do
  account_slug = params['account']
  job_slug = params['job']

  # approve job
  job = current_job(account_slug, job_slug)
  job.approved = false

  store = YAML::Store.new "./data/#{account_slug}/jobs.store"
  store.transaction do
    store[job_slug] = job
  end

  # confirm job
  # confirm_job_post(account_slug)

  redirect "/admin/#{params['account']}/jobs"
end

# Delete existing job
delete '/admin/:account/jobs/:job/delete' do
  account_slug = params['account']
  job_slug = params['job']

  # delete job
  store = YAML::Store.new "./data/#{account_slug}/jobs.store"
  store.transaction do
    store.delete(job_slug)
  end

  redirect "/admin/#{params['account']}/jobs"
end

# View all categories
get '/admin/:account/categories' do
  account_slug = params['account']
  @categories = get_all_categories(account_slug)
  erb :"admin/categories", :layout => :"admin/home"
end

# New category form
get '/admin/:account/categories/new' do
  @category = OpenStruct.new()
  erb :"admin/new_category", :layout => :"admin/home"
end

# Add a new category
post '/admin/:account/categories/create' do
  account_slug = params['account']
  category_slug = create_slug(params['name'])

  category = OpenStruct.new(
    name: params['name'],
    slug: category_slug
  )

  # save category
  store = YAML::Store.new "./data/#{account_slug}/categories.store"
  store.transaction do
    store[category_slug] = category
  end

  redirect "/admin/#{account_slug}/categories"
end

# Edit a category form
get '/admin/:account/categories/:category/edit' do
  account_slug = params['account']
  category_slug = params['category']
  @category = get_category(account_slug, category_slug)
  erb :"admin/edit_category", :layout => :"admin/home"
end

# Update existing category
patch '/admin/:account/categories/:category/update' do
  account_slug = params['account']
  old_slug = params['category']

  new_category = params['name']
  new_slug = create_slug(params['name'])

  store = YAML::Store.new "./data/#{account_slug}/categories.store"
  store.transaction do
    store.delete(old_slug)
  end

  category = OpenStruct.new(
    name: new_category,
    slug: new_slug
  )

  store.transaction do
    store[new_slug] = category
  end

  jobs_queue = []
  jobs = YAML::Store.new "./data/#{account_slug}/jobs.store"
  jobs.transaction(true) do  # begin read-only transaction, no changes allowed
    jobs.roots.each do |data_root_name|
      job = jobs[data_root_name]

      if job.category == old_slug
        jobs_queue.append(job)
      end
    end
  end

  jobs_queue.each do |job|
    # update category slug
    job.category = new_slug

    # save updated job
    job_slug = job.slug
    jobs.transaction do
      jobs[job_slug] = job
    end
  end

  redirect "/admin/#{account_slug}/categories"
end

# Delete a category
delete '/admin/:account/categories/:category/delete' do
  account_slug = params['account']
  category_slug = params['category']

  store = YAML::Store.new "./data/#{account_slug}/categories.store"
  store.transaction do
    store.delete(category_slug)
  end

  jobs_queue = []
  jobs = YAML::Store.new "./data/#{account_slug}/jobs.store"
  jobs.transaction(true) do  # begin read-only transaction, no changes allowed
    jobs.roots.each do |data_root_name|
      job = jobs[data_root_name]

      if job.category == category_slug
        jobs_queue.append(job)
      end
    end
  end

  jobs_queue.each do |job|
    # update category slug
    job.category = ''

    # save updated job
    job_slug = job.slug
    jobs.transaction do
      jobs[job_slug] = job
    end
  end

  redirect "/admin/#{account_slug}/categories"
end

# Populate with default settings
get '/admin/:account/settings' do
  @subscriber_count = subscriber_count(params["account"])
  erb :"admin/settings", :layout => :"admin/home"
end

# Update board settings
patch '/admin/:account/settings/board-update' do
  account_slug = params['account']

  # Find account and update values
  @settings.org_name = params["org_name"]
  @settings.org_bio = params["org_bio"]
  @settings.posting_offer = params["posting_offer"]
  @settings.homepage = params["homepage"]
  @settings.google_analytics = params["google-analytics"]
  @settings.job_expiry = params["job_expiry"].to_i
  @settings.moderation = params["moderation"]
  @settings.digest = params['digest']

  # save settings
  store = YAML::Store.new "./data/#{account_slug}/settings.store"
  store.transaction do
    store[account_slug] = @settings
  end

  redirect "/admin/#{account_slug}/settings"
end

# Update theme settings
patch '/admin/:account/settings/theme-update' do
  account_slug = params['account']

  # Find account and update values
  @settings.font_family = params["font_family"]
  @settings.accent_color = params["accent_color"]
  @settings.bg_color = params['bg_color']
  @settings.dark_mode = params['dark_mode']

  # save settings
  store = YAML::Store.new "./data/#{account_slug}/settings.store"
  store.transaction do
    store[account_slug] = @settings
  end

  redirect "/admin/#{account_slug}/settings"
end

# Update account logo
patch '/admin/:account/settings/logo' do
  account_slug = params['account']

  if params['logo'] && params['logo']['filename']
    filename = params['logo']['filename']
    file = params['logo']['tempfile']

    # Create unique filename
    date = Time.now
    new_filename = date.strftime('%s') + '-' + filename
    path = "./public/logos/#{new_filename}"

    # Write file to disk
    File.open(path, 'wb') do |f|
      f.write(file.read)
    end

    # Save path in model
    @settings.logo = new_filename

    # save settings
    store = YAML::Store.new "./data/#{account_slug}/settings.store"
    store.transaction do
      store[account_slug] = @settings
    end

  end

  redirect "/admin/#{account_slug}/settings"
end

# Remove account logo
delete '/admin/:account/settings/logo' do
  account_slug = params['account']

  @settings.logo = ''

  # save settings
  store = YAML::Store.new "./data/#{account_slug}/settings.store"
  store.transaction do
    store[account_slug] = @settings
  end

  redirect "/admin/#{account_slug}/settings"
end

get '/admin/:account/payment' do
  stripe_id = @settings.stripe_id

  if stripe_id
    stripe_account = Stripe::Account.retrieve(stripe_id)

    if stripe_account.charges_enabled
      @charges = 'yes'
    else
      @charges = 'no'
    end
  end

  erb :"admin/payment", :layout => :"admin/home"
end

# Update account settings
patch '/admin/:account/payment/update' do
  account_slug = params['account']

  # Find account and update values
  @settings.job_price = params["job_price"].to_i
  @settings.featured_price = params["featured_price"].to_i
  @settings.featured_option = params["featured_option"]

  # save settings
  store = YAML::Store.new "./data/#{account_slug}/settings.store"
  store.transaction do
    store[account_slug] = @settings
  end

  redirect "/admin/#{account_slug}/payment"
end

# Populate with default settings
post '/admin/:account/payment/stripe' do
  account_slug = params['account']
  origin = request_headers['origin']

  account = Stripe::Account.create(type: 'standard')
  session[:account_id] = account.id

  @settings.stripe_id = account.id
  store = YAML::Store.new "./data/#{account_slug}/settings.store"
  store.transaction do
    store[account_slug] = @settings
  end

  account_link = Stripe::AccountLink.create(
    type: 'account_onboarding',
    account: account.id,
    refresh_url: "#{origin}/admin/#{account_slug}/payment/stripe/refresh",
    return_url: "#{origin}/admin/#{account_slug}/payment"
  )

  { url: account_link.url }.to_json
end

get '/admin/:account/payment/stripe/refresh' do
  account_slug = params['account']
  redirect "/admin/#{account_slug}/payment" if session[:account_id].nil?

  account_id = session[:account_id]
  origin = "http://#{request_headers['host']}"

  account_link = Stripe::AccountLink.create(
    type: 'account_onboarding',
    account: account_id,
    refresh_url: "#{origin}/admin/#{account_slug}/payment/stripe/refresh",
    return_url: "#{origin}/admin/#{account_slug}/payment"
  )

  redirect account_link.url
end

# Get domain settings
get '/admin/:account/domain' do
  erb :"admin/domain", :layout => :"admin/home"
end

# Update domain settings
patch '/admin/:account/domain/update' do
  account_slug = params['account']

  # Find account and update values
  domain = params["domain"]

  # process domain address
  uri = URI.parse(domain)
  host = uri.host

  # Check for duplicate
  if existing_domains.include? host
    @message = 'There is already an account using that domain name. Please try another one or contact support.'
    erb :"admin/domain", :layout => :"admin/home"
  else
    @settings.domain = host

    # save settings
    store = YAML::Store.new "./data/#{account_slug}/settings.store"
    store.transaction do
      store[account_slug] = @settings
    end

    redirect "/admin/#{account_slug}/domain"
  end
end


# 404 and 500 route handlers
not_found do
  status 404
  erb :'404', :layout => :home
end

error do
  status 500
  # @error = request.env['sinatra_error'].name
  erb :'500', :layout => :home
end
