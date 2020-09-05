require 'sinatra'
require 'sinatra/content_for'
require 'sinatra/namespace'
require 'sinatra/subdomain'
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
  accounts = YAML::Store.new "./data/accounts.store"
  account = accounts.transaction { accounts[slug] }
end

def current_jobs(slug)
  jobs = []
  store = YAML::Store.new "./data/jobs-#{slug}.store"

  store.transaction(true) do
    store.roots.each do |data_root_name|
      jobs.append(store[data_root_name])
    end
  end

  return jobs
end

def current_job(account_slug, job_slug)
  store = YAML::Store.new "./data/jobs-#{account_slug}.store"
  job = store.transaction { store[job_slug] }
end

def add_job(account_slug, job)
  store = YAML::Store.new "./data/jobs-#{account_slug}.store"

  store.transaction do
    store[job.slug] = job
  end
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
  mb_obj.body_html "<p>Thanks for creating a job board with us!</p> <p>We have video tutorials and documentation to help you get started, you can view them here: http://www.tryferret.com/docs</p> <p>If you have any questions or feedback, please reach out: support@tryferret.com</p>"

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
  mb_obj.body_html "<p>You recently tried to reset your password.</p> <p>We have auto-generated one for your convenience: <strong>#{password}<strong></p> <p>If you have any questions or feedback, please reach out: support@tryferret.com</p>"

  mg_client.send_message 'mg.tryferret.com', mb_obj
end


# Landing page routes
get '/' do
  erb :index, :layout => :home
end

get '/docs' do
  erb :docs, :layout => :home
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
    adjectives = ['big', 'fat', 'happy', 'silly', 'proud', 'plain', 'clean', 'chubby', 'scary', 'clumsy']
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
    @message = 'There is already an account using that email or organization name.'
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
      org_bio: params['org-bio'],
      font_family: '',
      accent_color: 'blue',
      logo: '',
      domain: '',
      google_analytics: '',
      job_price: 0,
      job_expiry: 90,
      posting_offer: 'Your job listing will be posted for 90 days.',
      slug: slug
    )

    # Send welcome emails
    send_welcome_email(user.email)

    users.transaction do
      users[user.email] = user
    end

    accounts.transaction do
      accounts[account.slug] = account
    end

    FileUtils.cp("./data/jobs.store", "./data/jobs-#{slug}.store")

    @slug = slug
    erb :confirmation, :layout => :home
  end
end

# Admin routes
['/admin/:account', '/admin/:account/*'].each do |path|
  before path do
    account_slug = params['account']
    p "logged in? #{logged_in?}"
    if logged_in?
      p "current user: #{current_user}"
      p "account slug: #{current_user.account_slug}"
      if current_user.account_slug == account_slug
        @account = current_account(account_slug)
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
  @markdown_template = "\r\n\r\n## Responsibilities\r\n- List the job responsibilities out \r\n\r\n## Requirements\r\n- List the job requirements out \r\n\r\n## Company Background\r\n"
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
    company_name: params["company-name"],
    location: params["location"],
    company_url: params["company-url"],
    company_logo: new_filename || '',
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
  job.company_name= params["company-name"]
  job.location = params["location"]
  job.company_url = params["company-url"]

  # save job
  store = YAML::Store.new "./data/jobs-#{account_slug}.store"
  store.transaction do
    store[job_slug] = job
  end

  redirect "/admin/#{params['account']}/jobs"
end

# Delete existing job
delete '/admin/:account/jobs/:job/delete' do
  account_slug = params['account']
  job_slug = params['job']

  # delete job
  store = YAML::Store.new "./data/jobs-#{account_slug}.store"
  store.transaction do
    store.delete(job_slug)
  end

  redirect "/admin/#{params['account']}/jobs"
end

# Populate with default settings
get '/admin/:account/settings' do
  erb :"admin/settings", :layout => :"admin/home"
end

# Update account settings
patch '/admin/:account/settings/update' do
  account_slug = params['account']

  # Find account and update values
  @account.org_name = params["org_name"]
  @account.org_bio = params["org_bio"]
  @account.homepage = params["homepage"]
  @account.google_analytics = params["google-analytics"]
  @account.font_family = params["font_family"]
  @account.accent_color = params["accent_color"]
  @account.job_expiry = params["job_expiry"].to_i
  @account.posting_offer = params["posting_offer"]

  # save settings
  store = YAML::Store.new "./data/accounts.store"
  store.transaction do
    store[account_slug] = @account
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
    @account.logo = new_filename

    # save settings
    store = YAML::Store.new "./data/accounts.store"
    store.transaction do
      store[account_slug] = @account
    end

  end

  redirect "/admin/#{account_slug}/settings"
end

get '/admin/:account/payment' do
  stripe_id = @account.stripe_id

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
  @account.job_price = params["job_price"].to_i

  # save settings
  store = YAML::Store.new "./data/accounts.store"
  store.transaction do
    store[account_slug] = @account
  end

  redirect "/admin/#{account_slug}/payment"
end

# Populate with default settings
post '/admin/:account/payment/stripe' do
  account_slug = params['account']
  origin = request_headers['origin']

  account = Stripe::Account.create(type: 'standard')
  session[:account_id] = account.id

  @account.stripe_id = account.id
  store = YAML::Store.new "./data/accounts.store"
  store.transaction do
    store[account_slug] = @account
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
    @account.domain = host

    # save settings
    store = YAML::Store.new "./data/accounts.store"
    store.transaction do
      store[account_slug] = @account
    end

    redirect "/admin/#{account_slug}/domain"
  end
end

subdomain do
  before do
    @subdomain = subdomain
    @account = current_account(subdomain)
  end

  # View all jobs
  get '/' do
    all_jobs = current_jobs(@subdomain)
    @jobs = []

    expiry_days = @account.job_expiry.to_i

    if expiry_days == 0
      @jobs = all_jobs
    else
      all_jobs.each do |job|
        next if job.paid == false
        job_date = Time.parse(job.date)
        today = Time.now
        diff = ((today - job_date) / 86400).round
        @jobs.append(job) if diff < expiry_days
      end
    end

    @jobs = @jobs.reverse()

    erb :"board/jobs", :layout => :"board/layout"
  end

  # New job form
  get '/jobs/new' do
    @markdown_template = "\r\n\r\n## Responsibilities\r\n- List the job responsibilities out \r\n\r\n## Requirements\r\n- List the job requirements out \r\n\r\n## Company Background\r\n"
    @job = OpenStruct.new()
    erb :"board/new", :layout => :"board/layout"
  end

  # Create a new job
  post '/jobs/create' do
    store = YAML::Store.new "./data/jobs-#{@subdomain}.store"

    # Check if job already exists
    date = Time.now
    combined_string = params['position'] + '-' + params['company-name'] + '-' + date.strftime('%s')
    @job_slug = create_slug(combined_string)

    existing_job = store.transaction { store.fetch(@job_slug, false) }

    if existing_job
      erb :"board/duplicate_job", :layout => :"board/layout"
    else
      if @account.job_price.to_i > 0
        paid = false
      else
        paid = true
      end

      @jid = SecureRandom.uuid

      job = OpenStruct.new(
        position: params["position"],
        description: params["description"],
        application: params["application"],
        company_name: params["company-name"],
        location: params["location"],
        company_url: params["company-url"],
        contact: params["contact"],
        owner: params["owner"],
        edit_id: @jid,
        date: date.to_s,
        paid: paid,
        slug: @job_slug
      )

      add_job(@subdomain, job)

      if @account.job_price.to_i > 0
        redirect "/jobs/#{@job_slug}/pay"
      else
        redirect "/jobs/#{@job_slug}/confirm"
      end

    end
  end

  # Page with form to search jobs
  get '/search' do
    erb :"board/search", :layout => :"board/layout"
  end

  # Search jobs post route
  post '/search' do
    # Need to convert multiple words to substring
    search_term = params['query']

    job_slug = params['job']
    @all_jobs = current_jobs(@subdomain)
    @jobs = []

    @all_jobs.each do |job|
      if job.position.include? search_term or job.description.include? search_term or job.location.include? search_term or job.company_name.include? search_term
        @jobs.append(job)
      end
    end

    erb :"board/search", :layout => :"board/layout"
  end

  # View a single job
  get '/jobs/:job' do
    job_slug = params['job']
    @job = current_job(@subdomain, job_slug)

    erb :"board/job", :layout => :"board/layout"
  end

  get '/jobs/:job/pay' do
    @job_slug = params['job']

    erb :"board/payment", :layout => :"board/layout"
  end

  # Pay for a job posting
  post '/jobs/:job/pay' do
    job_slug = params['job']
    origin = request_headers['origin']
    stripe_amount = @account.job_price.to_i * 100
    stripe_id = @account.stripe_id
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
      success_url: "#{origin}/jobs/#{job_slug}/confirm",
      cancel_url: "#{origin}/jobs/#{job_slug}/problem",
    )

    { id: session.id }.to_json
  end

  # Give user edit job link and confirmation details
  get '/jobs/:job/confirm' do
    @job_slug = params['job']
    job = current_job(@subdomain, @job_slug)
    @jid = job.edit_id

    # Mark job as paid
    job.paid = true

    store = YAML::Store.new "./data/jobs-#{@subdomain}.store"
    store.transaction do
      store[@job_slug] = job
    end

    erb :"board/confirmation", :layout => :"board/layout"
  end

  # Problem with CC page
  get '/jobs/:job/problem' do
    @account_slug = @account.slug
    @job_slug = params['job']
    erb :"board/problem", :layout => :"board/layout"
  end

  # Unique link to edit an existing job
  get '/jobs/:job/:edit_id/edit' do
    job_slug = params['job']
    @job = current_job(@subdomain, job_slug)

    if @job.edit_id == params['edit_id']
      erb :"board/edit", :layout => :"board/layout"
    else
      redirect "/"
    end
  end

  # Update existing job
  patch '/jobs/:job/:edit_id/update' do

    # Find job
    job_slug = params['job']
    job = current_job(@subdomain, job_slug)

    if job.edit_id == params['edit_id']
      # replace values
      job.position = params["position"]
      job.description = params["description"]
      job.application = params["application"]
      job.company_name = params["company-name"]
      job.location = params["location"]
      job.company_url = params["company-url"]
      job.contact = params["contact"]
      job.owner = params["owner"]

      # save job
      store = YAML::Store.new "./data/jobs-#{@subdomain}.store"
      store.transaction do
        store[job_slug] = job
      end

      redirect "/jobs/#{job_slug}"
    else
      redirect "/"
    end
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
