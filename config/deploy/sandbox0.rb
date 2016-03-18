# Define your release to be deployed to integration environment here.
# Release number for integration environment is supposed to be odd numbers.
set :branch, 'REL_1_2_0'

# Define your repository server for integration environment here.
#   production SVN - svn.prod.laxigames.com
#   development SVN - svn.mo.laxino.com
set :repo_host, 'svn.prod.laxigames.com'

# Define your application servers for integration environment here.
#   int - Integration
#   stg - Staging
#   prd - Production
role :app, 'ph-snd-sso-app01.laxigames.com'

#role :cronjob_app, 'int-cons-vapp03.rnd.laxino.com'

# Define your database servers for integration environment here.
# role :db,  "int-cons-db01.rnd.laxino.com", :primary => true

# Define your application cluster with Nginx settings here
# These variables will be used in generating Nginx/Thin config files
set :nginx_worker_processes, 2
set :cluster_port, 10046
set :virtual_server_name, 'ph-snd-sso-vapp01.laxigames.com'
set :num_of_servers, 2
