def run_command(variable)
	changes = `#{variable}`
	unless changes.empty?
	puts "#{variable}"
	puts "#{changes}"
	puts
	end
end

desc "Deploy."
task :deploy => %w(deploy:before deploy:push deploy:after)

desc "Set up deployment prerequisites."
task "deploy:newb" do
  %w(heroku taps).each do |gem|
    puts "gem install #{gem}" unless Gem.available? gem
  end

  Deploy::ENVIRONMENTS.each do |branch, env|
    unless /^#{env}/ =~ `git remote`
      puts "git remote add heroku-#{env} git@heroku.com:#{$app}-#{env}.git"
      #puts "git fetch origin/#{env}"

      unless /#{branch}$/ =~ `git branch`
        puts "git branch #{branch} origin/#{env}"
      end
    end
  end
end

desc "Show undeployed changes."
task "deploy:pending" do
  env    = Deploy.env
  source = "origin/#{env}"
  target = "#{Deploy.branch}"
  cmd    = "git log #{target}..#{source} '--format=tformat:%s|||%aN|||%aE'"

  changes = `#{cmd}`.split("\n").map do |line|
    msg, author, email = line.split("|||").map { |e| e.empty? ? nil : e }
    msg << " [#{author || email}]" unless Deploy::PEOPLE.include? email 
    msg
  end

  last = `git show --pretty=%cr #{target}`.split("\n").first
  puts "Last deploy to #{env} was #{last || 'never'}."

  unless changes.empty?
    puts
    changes.each { |change| puts "* #{change}" }
    puts
  end
end

# The push.

desc "Push the recent changes to heroku"
task("deploy:push") do 
print "Continue deploying '#{Deploy.env}' to heroku? (y/n) " and STDOUT.flush
        char = $stdin.getc
        if char != ?y && char != ?Y
         puts "Deploy aborted"
         exit 
        end
	sh "git push heroku-#{Deploy.env} #{Deploy.branch}:master"
	#sh "heroku rake hoptoad:deploy TO=#{Deploy.rails_env}  --app #{$app}-#{Deploy.env}"
	migrate = "heroku rake db:migrate --app #{$app}-#{Deploy.env} RAILS_ENV=#{Deploy.rails_env}"
	run_command migrate 

	create_indexes = "heroku rake db:mongoid:create_indexes --app #{$app}-#{Deploy.env} RAILS_ENV=#{Deploy.rails_env}"
	run_command create_indexes 
	sh "heroku restart --app #{$app}-#{Deploy.env}"
end

desc "Destroy the App"
task("deploy:app:destroy") do
	sh "heroku destroy --app #{$app}-#{Deploy.env}"
end

desc "Destroy the Databases and re-create indexes"
task("deploy:db:reset") do
 sh "heroku pg:reset --app #{$app}-#{Deploy.env} --db DATABASE_URL --confirm #{$app}-#{Deploy.env}"
sh "heroku console --app #{$app}-#{Deploy.env} `cat clean_mongodb.rb`"
 sh "heroku rake --trace db:mongoid:cleanup_old_collections --app #{$app}-#{Deploy.env}"
 #sh "heroku rake --trace db:mongoid:cleanup_old_collections --app #{$app}-#{Deploy.env} RAILS_ENV=#{Deploy.rails_env}"

 Rake.application.invoke_task("deploy:db:migrate")

# sh "heroku rake --trace db:migrate --app #{$app}-#{Deploy.env} RAILS_ENV=#{Deploy.rails_env}"
# sh "heroku rake --trace db:mongoid:create_indexes --app #{$app}-#{Deploy.env} RAILS_ENV=#{Deploy.rails_env}"
#	sh "heroku restart --app #{$app}-#{Deploy.env}"
end

desc "Create a new App"
task("deploy:app:create") do
 sh "heroku create #{$app}-#{Deploy.env} --remote heroku-#{Deploy.env}" 
 stack = "heroku stack:migrate bamboo-mri-1.9.2 --app #{$app}-#{Deploy.env}"
 run_command stack 
 rack = "heroku config:add RACK_ENV=#{Deploy.rails_env} --app #{$app}-#{Deploy.env}"
 run_command rack 
end

task "deploy:addons" do
  Deploy::ADDONS.each do |addon|
	cmd = "heroku addons:#{addon} --app #{$app}-#{Deploy.env}"
	run_command cmd
  end

	# deployhook is special
    sh "heroku addons:add deployhooks:email recipient=ak@whoishere.info subject=\"[Heroku] {{app}} deployed\" body=\"{{user}} deployed {{head}} to {{url}} {{git_log}}\" --app #{$app}-#{Deploy.env}"
end

task "deploy:db:migrate" do
	puts "Setting up DB for #{Deploy.env}"

	migrate = "heroku rake --trace db:migrate --app #{$app}-#{Deploy.env} RAILS_ENV=#{Deploy.rails_env}"
	run_command migrate 

	create_indexes = "heroku rake --trace db:mongoid:create_indexes --app #{$app}-#{Deploy.env}"
	run_command create_indexes 
	sh "heroku restart --app #{$app}-#{Deploy.env}"
end

task "deploy:prepare:all" do
  Deploy::ENVIRONMENTS.each do |branch, env|
	puts "Setting up DB for #{Deploy.env}"

  Deploy::ADDONS.each do |addon|
	cmd = "heroku addons:#{addon} --app #{$app}-#{branch}"
	run_command cmd
  end 
  end
end

task "deploy:before" do
  if /\.gems/ =~ `git status`
    abort "Changed gems. Commit '.gems' and deploy again."
  end

  ENV["TO"] = "#{Deploy.rails_env}" 
  ENV["REPO"] = "git@github.com:goof/#{$app}.git"
end

# Hooks. Attach extra behavior with these.

task "deploy:before" => "deploy:pending"
task "deploy:after" => %w(deploy:before hoptoad:deploy)

module Deploy

  # A map of local branches to deployment environments.

  ENVIRONMENTS = { "master" => "production", "develop" => "develop"}
  RACKENV = { "svapna" => "production"}
  RACKENV = { "svapna-test" => "development"}

  # The folks who are most likely to be committing. People who
  # aren't in this list get their names next to their commit
  # messages, so I can see what contractors are doing.

  PEOPLE = ["abhinav.sarje@gmail.com"]
  ADDONS = ["add mongohq:free", "upgrade logging:expanded", "add newrelic:standard",
            "add redistogo:nano"]
  test = ENV['TEST']
  if test.blank?
  	$app = "svapna"
  else
  	$app = "svapna" + "-" + "test"
  end
  puts #{ENV['TEST']}

  # What's the current deployment environment?

  def self.env
    return @env if defined? @env

    unless /^\* (.*)$/ =~ `git branch`
      abort "I can't figure out which branch you're on."
    end

    branch = $1
    @branch = $1

    #branch = branch.sub(/feature\//, '')
    #branch = branch.gsub(/_/, '-')

    unless Deploy::ENVIRONMENTS.include? branch
      abort "I don't know how to deploy '#{branch}'."
    end

    @env = ENVIRONMENTS[branch]
  end

  def self.branch
    unless /^\* (.*)$/ =~ `git branch`
      abort "I can't figure out which branch you're on."
    end

    @branch = $1
  end
  def self.rails_env
    @rails_env = RACKENV["#{$app}"] 
  end
end
