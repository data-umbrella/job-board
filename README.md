# README for job board app

The application is a job board. Visitors can view jobs and submit new jobs. Admins can moderate job postings.

## How to run the code

[TBD] Create docker image and put instructions here

## Explain the code

The codebase is built on Ruby's Sinatra. It's a micro framework. All the routes are contained in the `server.rb` file. The app doesn't use a traditional database, the data is stored using native Ruby objects and YAML flat files.

- The first section is the package imports.
- The second section is the framework settings.
- The third section is the helper functions, these are mostly logic that is repeated multiple times during the routes, like getting a specific job from the database.
- The fourth section is the authentication routes like logging in and logging out.
- The fifth section is the public job routes, like viewing all the jobs or an individual job. This section heavily uses the helper functions.
- The sixth section is the admin routes, like adding/editing/deleting jobs.
- The seventh section is the error handler routes.

## Useful commands

- `ruby server.rb` - Run the app locally.
- `rerun 'ruby server.rb'` - Allows you to run the app locally and it refreshes when you update the codebase. Will need to install the `rerun` gem.
