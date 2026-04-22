max_threads_count = ENV.fetch('RAILS_MAX_THREADS') { 5 }.to_i
min_threads_count = ENV.fetch('RAILS_MIN_THREADS') { max_threads_count }.to_i
threads min_threads_count, max_threads_count

port        ENV.fetch('PORT') { 3000 }
environment ENV.fetch('RAILS_ENV') { 'development' }

# Clustered mode in production: spawn N workers (forked processes), each with
# its own thread pool. Effective concurrency = WEB_CONCURRENCY * RAILS_MAX_THREADS.
# Disable on small VPSs by setting WEB_CONCURRENCY=0 (single-process mode).
if ENV['RAILS_ENV'] == 'production'
  workers ENV.fetch('WEB_CONCURRENCY') { 2 }.to_i
  preload_app!

  # Reset DB and Redis (Action Cable) connections after fork so each worker
  # has its own pool. Without this, workers share file descriptors and the
  # first worker to use a connection corrupts it for the others.
  before_fork do
    ActiveRecord::Base.connection_pool.disconnect! if defined?(ActiveRecord)
  end

  on_worker_boot do
    ActiveRecord::Base.establish_connection if defined?(ActiveRecord)
  end
end

# Allow puma to be restarted by `rails restart` command.
plugin :tmp_restart
