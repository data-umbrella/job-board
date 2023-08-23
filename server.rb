# 1 - Import packages

# gem install puma puma-daemon
# gem install sinatra sinatra-contrib
require 'sinatra'
require 'sinatra/content_for'
require 'sinatra/namespace'

# gem install bcrypt dotenv
require 'bcrypt'
require 'dotenv'

# native modules, no install needed
require 'securerandom'
require 'yaml/store'
require 'ostruct'
require 'date'

# 2- Load settings
Dotenv.load
set :environment, ENV['RACK_ENV'].to_sym
# hide errors in dev, not showing in prod
# set :show_exceptions, false
Tilt.register Tilt::ERBTemplate, 'html.erb'
# Stripe.api_key = ENV['STRIPE_API_KEY']
MASTER_PASS = ENV['PASSWORD']

if settings.development?
  p 'running in development'
end

if settings.production?
  p 'running in production'
  # require 'rack/ssl-enforcer'
  # use Rack::SslEnforcer
end

enable :sessions

# 3- Setup helper functions
helpers do
  # Internal HTTP helpers
  def get_environment
    ENV['RACK_ENV']
  end

  def request_headers
    env.each_with_object({}) { |(k, v), acc| acc[Regexp.last_match(1).downcase] = v if k =~ /^http_(.*)/i; }
  end

  # Text modification helpers
  def truncate(string, max)
    string.length > max ? "#{string[0...max]}..." : string
  end

  def create_slug(text)
    text.downcase.strip.gsub(' ', '-').gsub(/[^\w-]/, '')
  end

  # Authentication helpers
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

  # Flat file storage helpers
  def current_account(slug)
    store = YAML::Store.new "./data/accounts.store"
    item = store.transaction { store[slug] }
  end

  def current_settings(slug)
    store = YAML::Store.new "./data/settings.store"
    item = store.transaction { store[slug] }
  end

  def current_jobs()
    jobs = []
    store = YAML::Store.new "./data/jobs.store"

    store.transaction(true) do
      store.roots.each do |data_root_name|
        jobs.append(store[data_root_name])
      end
    end

    return jobs
  end

  def current_job(slug)
    store = YAML::Store.new "./data/jobs.store"
    job = store.transaction { store[slug] }
  end

  def add_job(job)
    store = YAML::Store.new "./data/jobs.store"

    store.transaction do
      store[job.slug] = job
    end
  end

  def get_all_categories()
    items = []
    store = YAML::Store.new "./data/categories.store"

    store.transaction(true) do
      store.roots.each do |data_root_name|
        items.append(store[data_root_name])
      end
    end

    sorted_items = items.sort_by { |el| el.name }

    return sorted_items
  end

  def get_category(slug)
    store = YAML::Store.new "./data/categories.store"
    item = store.transaction { store[slug] }
    return item
  end

  # Larger combined helpers
  def get_job_edit_page()
    job_slug = params['job']
    @job = current_job(job_slug)
    @categories = get_all_categories()

    erb :"board/edit", :layout => :"board/layout"
  end

  def get_all_jobs()

    all_jobs = current_jobs()

    # checks for expired jobs and paid and approved jobs
    expiry_days = 120
    jobs = []

    # Sort in time order
    all_jobs.reverse!

    all_jobs.each_with_index do |job, index|

      if expiry_days > 0
        job_date = Time.parse(job.date)
        today = Time.now
        diff = ((today - job_date) / 86400).round

        if diff < expiry_days
            jobs.append(job)
        else
          next
        end
      else
        next
      end
    end

    return jobs
  end

  def create_new_job()
    store = YAML::Store.new "./data/jobs.store"

    # Check if job already exists
    date = Time.now
    combined_string = params['position'] + '-' + params['company-name'] + '-' + date.strftime('%s')
    job_slug = create_slug(combined_string)

    existing_job = store.transaction { store.fetch(job_slug, false) }

    if existing_job
      erb :"board/duplicate_job", :layout => :"board/layout"
    else
      paid = true

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

      add_job(job)

      @jid = jid
      @job_slug = job_slug

      redirect "/jobs/#{job_slug}/confirm"
    end
  end
end

# 4 - Auth routes
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
    redirect "/admin"
  else
    @message = 'The username or password you entered was incorrect.'
    erb :login, :layout => :home
  end
end

post '/logout' do
  session.clear
  redirect '/'
end

# 5 - Public job board routes
get '/' do
  @jobs = get_all_jobs()
  @categories = get_all_categories()
  erb :"board/jobs", :layout => :"board/layout"
end

# # View the new job form
# get '/jobs/new' do
#   @html_template = "<p><br></p><h2>Responsibilities </h2><ul><li>List the job responsibilities
#     out </li></ul><p><br></p><h2>Requirements</h2><ul><li>List the job requirements
#     out</li></ul><p><br></p><h2>Company Background</h2><p><br></p><p><br></p><p><br></p>"
#   @categories = get_all_categories()
#   @job = OpenStruct.new()
#   erb :"board/new", :layout => :"board/layout"
# end
#
# # Create a new job
# post '/jobs/create' do
#   create_new_job()
# end

# Creates an X-Frame embed
get '/embed' do
  @jobs = get_all_jobs().first(5)
  headers({ 'X-Frame-Options' => '' })
  erb :"embed/preview", :layout => :"embed/layout"
end

# Page with form to search jobs
get '/search' do
  erb :"board/search", :layout => :"board/layout"
end

# Search jobs post route
post '/search' do
  search_term = params['query'].downcase
  all_jobs = get_all_jobs()
  @jobs = []

  all_jobs.each do |job|
    if job.position.downcase.include? search_term or job.description.downcase.include? search_term or job.location.downcase.include? search_term or job.company_name.downcase.include? search_term
      @jobs.append(job)
    end
  end

  erb :"board/search", :layout => :"board/layout"
end

# View a single category
get '/categories/:category' do
  slug = params['category']
  @category = get_category(slug)
  @jobs = get_category_jobs(slug)
  erb :"board/category", :layout => :"board/layout"
end

# View a single job
get '/jobs/:job' do
  slug = params['job']
  @job = current_job(slug)
  erb :"board/job", :layout => :"board/layout"
end

# Give user edit job link and confirmation details
get '/jobs/:job/confirm' do
  @slug = params['job']
  job = current_job(@slug)
  @jid = job.edit_id

  erb :"board/confirmation", :layout => :"board/layout"
end

# Unique link to edit an existing job
get '/jobs/:job/:edit_id/edit' do
  get_job_edit_page()
end

# Update existing job
patch '/jobs/:job/:edit_id/update' do
  slug = params['job']
  job = current_job(slug)

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
    store = YAML::Store.new "./data/jobs.store"
    store.transaction do
      store[slug] = job
    end

    redirect "/jobs/#{slug}"
  end
end

# 6 - Admin routes
['/admin', '/admin/*'].each do |path|
  before path do
    if logged_in?
      @slug = 'data-umbrella'
      @settings = current_settings(@slug)
      @account = current_account(@slug)
    else
      @message = "You don't have permission to do that."
      redirect '/login'
    end
  end
end

# View the dashboard
get '/admin' do
  erb :"admin/dashboard", :layout => :"admin/home"
end

# View all jobs
get '/admin/jobs' do
  @jobs = current_jobs()
  erb :"admin/jobs", :layout => :"admin/home"
end

# New job form
get '/admin/jobs/new' do
  @html_template = "<p><br></p><h2>Responsibilities </h2><ul><li>List the job responsibilities
    out </li></ul><p><br></p><h2>Requirements</h2><ul><li>List the job requirements
    out</li></ul><p><br></p><h2>Company Background</h2><p><br></p><p><br></p><p><br></p>"
  @categories = get_all_categories()
  @job = OpenStruct.new()
  erb :"admin/new", :layout => :"admin/home"
end

# Create a new job
post '/admin/jobs/create' do
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

  add_job(job)

  redirect "/admin/jobs"
end

# Form to edit existing job
get '/admin/jobs/:job/edit' do
  job_slug = params['job']
  @categories = get_all_categories()
  @job = current_job(job_slug)
  erb :"admin/edit", :layout => :"admin/home"
end

# Update existing job
patch '/admin/jobs/:job/update' do
  job_slug = params['job']
  job = current_job(job_slug)
  date = Time.now

  puts "date", date

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
  store = YAML::Store.new "./data/jobs.store"
  store.transaction do
    store[job_slug] = job
  end

  redirect "/admin/jobs"
end

# Delete existing job
delete '/admin/jobs/:job/delete' do
  job_slug = params['job']
  store = YAML::Store.new "./data/jobs.store"
  store.transaction do
    store.delete(job_slug)
  end

  redirect "/admin/jobs"
end

# 7 - 404 and 500 route handlers
not_found do
  status 404
  erb :'404', :layout => :home
end

error do
  status 500
  erb :'500', :layout => :home
end
