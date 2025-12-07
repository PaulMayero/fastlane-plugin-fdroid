module Fastlane
  module Actions
    module SharedValues
      FDROID_SET_UP_NIGHTLY_REPO_ON_GITLAB_CUSTOM_VALUE = :FDROID_SET_UP_NIGHTLY_REPO_ON_GITLAB_CUSTOM_VALUE
    end

    class FdroidSetUpNightlyRepoOnGitlabAction < Action
      def self.run(params)
        # fastlane will take care of reading in the parameter and fetching the environment variable:
        # UI.message("Parameter API Token: #{params[:api_token]}")

        # sh "shellcommand ./path"

        # Actions.lane_context[SharedValues::FDROID_NIGHTLY_CUSTOM_VALUE] = "my_val"
        path_to_android_project = params[:path_to_android_project]
        gitlab_access_token = params[:gitlab_personal_access_token]
        path_to_keystore = params[:path_to_keystore]
        # require 'pry'
        # require 'pry-byebug'
        # binding.pry
        path_to_android_project = File.expand_path(path_to_android_project)

        gitlab_username = get_gitlab_username(path_to_android_project)
        gitlab_repo_name = get_gitlab_reponame(path_to_android_project)

        hash_of_debug_keystore_and_deploy_key = run_fdroid_nightly_command(path_to_keystore)

        path_to_fdroid_nightly_yml_file = add_deploy_stage_in_gitlab_ci_yml(path_to_android_project)
        add_and_commit_fdroid_nightly_yml(path_to_fdroid_nightly_yml_file, path_to_android_project)

        hash_of_repo_name_and_link_to_nightly = create_online_gitlab_repo(gitlab_username, gitlab_access_token, gitlab_repo_name)
        add_debug_keystore_as_secret_to_repo(gitlab_username, gitlab_access_token, gitlab_repo_name, hash_of_debug_keystore_and_deploy_key)
        add_deploy_key_to_nightly_repo(gitlab_access_token, hash_of_debug_keystore_and_deploy_key, hash_of_repo_name_and_link_to_nightly, gitlab_username)
        print_out_next_steps_to_create_nightly(hash_of_debug_keystore_and_deploy_key, hash_of_repo_name_and_link_to_nightly)
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        'Create a Nightly Repo on Gitlab to access nightly versions of your App'
      end

      def self.details
        # Optional:
        # this is your chance to provide a more detailed description of this action
        'You can use this action to set up a F-Droid Nightly Repo on Gitlab.It is executed once on your master or main branch.'
      end

      def self.available_options
        # Define all options your action supports.

        # Below a few examples
        [
          FastlaneCore::ConfigItem.new(key: :path_to_android_project,
                                       # The name of the environment variable
                                       env_name: 'PATH_TO_ANDROID_PROJECT',
                                       # a short description of this parameter
                                       description: 'Complete File path to Android Project',
                                       verify_block: proc do |value|
                                         unless value && !value.empty?
                                           UI.user_error!("No Path given. Please try again")
                                         end
                                         # UI.user_error!("Couldn't find file at path '#{value}'") unless File.exist?(value)
                                       end,
                                       default_value: '.'),
          FastlaneCore::ConfigItem.new(key: :gitlab_personal_access_token,
                                       env_name: 'GITLAB_TOKEN',
                                       description: 'Developer Gitlab personal access token to be used to create the Nightly Repo on Gitlab',
                                       verify_block: proc do |value|
                                                       unless value && !value.empty?
                                                         UI.user_error("No Gitlab Personal token found, pass using `gitlab_personal_access_token: 'token'`")
                                                       end
                                                     end),
          FastlaneCore::ConfigItem.new(key: :path_to_keystore,
                                       env_name: 'PATH_TO_KEYSTORE',
                                       description: 'Path to Keystore to be used to generate F-Droid nightly DEBUG_KEYSTORE secret variable and SSH public key to be used as deploy key',
                                       verify_block: proc do |value|
                                                       unless value && !value.empty?
                                                         UI.message("No Keystore provided, you have to provide the keystore")
                                                       end
                                                     end),
          FastlaneCore::ConfigItem.new(key: :password_used_for_github_ssh_key,
                                       env_name: 'SSH_PASSWORD',
                                       description: 'Gitlab Password for the SSH key used',
                                       verify_block: proc do |value|
                                                       unless value && !value.empty?
                                                         UI.message("")
                                                       end
                                                     end,
                                       default_value: 'nil')
        ]
      end

      def self.return_value
        # If your method provides a return value, you can describe here what it does
      end

      def self.authors
        # So no one will ever forget your contribution to fastlane :) You are awesome btw!
        ['F-Droid']
      end

      def self.is_supported?(platform)
        true
      end

      def self.get_gitlab_username(path_to_android_project)
        # checks if there is any git repo and returns username
        require 'rugged'
        begin
          repo = Rugged::Repository.discover(path_to_android_project)
        rescue StandardError => e
          UI.error("Error: No Git Repo found. #{e.message}")
          UI.message("Please set up Gitlab repo then try again")
        else
          if repo.config['user.name'].nil?
            repo_url = repo.remotes['origin'].url
            gitlab_user = repo_url.split(%r{[:/]}).reject(&:empty?)
            if repo_url.start_with?("http")
              # extract repo name from http repo
              return gitlab_user[2]
            else
              # extract repo name from ssh repo
              return gitlab_user[1]
            end
          else
            return repo.config['user.name']
          end
        ensure
          repo&.close
        end
      end

      def self.run_fdroid_nightly_command(path_to_keystore)
        require 'open3'
        UI.message(path_to_keystore.to_s)
        if path_to_keystore.empty?
          UI.error("Create Custom Keystore to proceed")
          exit
        end

        unless path_to_keystore.empty?
          debug_keystore, deploy_key, status = Open3.capture3("fdroid nightly --show-secret-var --keystore #{path_to_keystore}")
        end

        if status.success?
          return {
            debug_keystore: debug_keystore, # debug.keystore encoded for the DEBUG_KEYSTORE secret variable
            deploy_key: deploy_key # SSH Public key, used as deploy key
          }
        end

        unless status.success?
          UI.error(deploy_key.to_s)
          exit
        end
      end

      def self.add_deploy_stage_in_gitlab_ci_yml(path_to_android_project)
        # create fdroid-nightly.yml
        require "fileutils"
        require "yaml"
        gitlab_ci_yml = File.join(path_to_android_project, '.gitlab-ci.yml')
        if File.exist?(gitlab_ci_yml)
          UI.message(".gitlab-ci.yml file has been found in the project")
          UI.message("is is at #{gitlab_ci_yml}")
          yaml_content = YAML.load_file(gitlab_ci_yml)
          hash_str_of_deploy_nightly = YAML.safe_load(self.yaml_string_for_fdroid_nightly)
          if yaml_content.key?("deploy_nightly")
            # replace the key and value with our yaml string
            yaml_content["deploy_nightly"] = hash_str_of_deploy_nightly["deploy_nightly"]
            # write out the content back to the file
            File.write(gitlab_ci_yml, yaml_content.to_yaml, encoding: "UTF-8")
            gitlab_ci_yml
          else
            # add yaml content fto file
            yaml_content["deploy_nightly"] = hash_str_of_deploy_nightly["deploy_nightly"]
            File.write(gitlab_ci_yml, yaml_content.to_yaml, encoding: "UTF-8")
            gitlab_ci_yml
          end
        else
          UI.message("No .gitlab-ci yml found in this project. Creating one for you")
          File.write(gitlab_ci_yml, self.yaml_string_for_fdroid_nightly, encoding: "UTF-8")
          UI.message("F-Droid Nightly job is written at #{gitlab_ci_yml}")
          gitlab_ci_yml
        end
      end

      def self.yaml_string_for_fdroid_nightly
        <<~YAML
          deploy_nightly:
              image: registry.gitlab.com/fdroid/fdroidserver:buildserver-bookworm
              stage: deploy
              variables:
                JAVA_HOME: /usr/lib/jvm/java-17-openjdk-amd64
              only:
                - master
              script:
                - test -z "$DEBUG_KEYSTORE" && exit 0
                - apt-get install -t bookworm-backports androguard fdroidserver
                - export versionCode=$(date '+%s')
                - sed -i "s,^|(|s*versionCode|)  *[0-9].*,|1 $versionCode," app/build.gradle*
                - ./gradlew assembleDebug
                - rm -rf $fdroidserver
                - fdroidserver="fdroidserver"
                - mkdir $fdroidserver
                - git ls-remote https://gitlab.com/fdroid/fdroidserver.git master
                - curl --silent https://gitlab.com/fdroid/fdroidserver/-/archive/master/fdroidserver-master.tar.gz| tar -xz --directory=$fdroidserver --strip-components=1
                - export PATH="$fdroidserver:$PATH"
                - export PYTHONPATH="$fdroidserver:$fdroidserver/examples"
                - export PYTHONUNBUFFERED=true
                - fdroid nightly -v
        YAML
      end

      def self.add_and_commit_fdroid_nightly_yml(path_to_yaml_file, path_to_android_project)
        require 'rugged'
        UI.message("gitlab.yml file is at #{path_to_yaml_file}")
        begin
          repo = Rugged::Repository.discover(path_to_android_project)
        rescue StandardError => e
          UI.error(e.to_s)
          UI.message("Rectify above error to continue")
          exit
        else
          # force add and commit file even if no changes
          index = repo.index
          # Add the file explicitly (force)
          UI.message("path is #{path_to_yaml_file}")
          file_path = path_to_yaml_file.split(File::SEPARATOR).reject(&:empty?).last(1).join(File::SEPARATOR)
          # file_path = path_to_yaml_file
          UI.message("file_path is #{file_path}")
          index.add(path: file_path, oid: Rugged::Blob.from_workdir(repo, file_path), mode: 0100644)
          # Write the index to a new tree
          tree_oid = index.write_tree(repo)

          # Set up commit author/committer
          author = {
            email: repo.config['user.email'] || "No email set",
            name:  repo.config['user.name']  || "No name set",
            time: Time.now
          }

          # Get parent commit if it exists
          parents = repo.empty? ? [] : [repo.head.target]

          # Create the commit
          Rugged::Commit.create(repo,
                                message: "Add fdroid-nightly.yml",
                                author: author,
                                committer: author,
                                tree: tree_oid,
                                parents: parents,
                                update_ref: 'HEAD')

          UI.message("Already added and commited .gitlab-ci.yml to your repo")
          # push to upstream using ssh
          remote = repo.remotes['origin']
          UI.message("Remote url is #{remote.url}")
          credentials = Rugged::Credentials::SshKey.new(
            username: 'git',
            privatekey: File.expand_path('~/.ssh/id_rsa'),
            passphrase: ENV.fetch('SSH_PASSWORD', nil)
          )
          UI.message("Pushing your changes to the online repo")
          # repo.push('origin', ['refs/heads/main'], credentials: credentials)
          repo.push('origin', [repo.head.name], credentials: credentials)
          UI.message("success in pushing to remote")
        ensure
          repo&.close
        end
      end

      def self.get_gitlab_reponame(path_to_android_project)
        # returns repo name
        require 'rugged'
        begin
          repo = Rugged::Repository.discover(path_to_android_project)
        rescue StandardError => e
          UI.error("Error: No Git Repo found. #{e.message}")
          UI.message("Please set up GitLab repo then try again")
          exit
        else
          repo_url = repo.remotes['origin'].url
          repo_url.split(%r{[:/]})[-1].gsub(".git", "")
        ensure
          repo&.close
        end
      end

      def self.create_online_gitlab_repo(gitlab_username, gitlab_access_token, name_of_repo)
        # deletes nightly repo on Gitlab if exists
        # Recreates repo for re-deployment
        require 'gitlab'

        gitlab = Gitlab.client(endpoint: "https://gitlab.com/api/v4", private_token: gitlab_access_token)

        UI.message("the user is #{gitlab.user.username}")

        repo_name = "#{name_of_repo}-nightly"
        repo_description = "This will be the F-Droid nightly repo of #{name_of_repo}"
        # private_repo = false

        # Get your own namespace ID
        user = gitlab.user
        UI.message("user is #{user.username}")
        namespace_id = gitlab.namespaces(search: user.username).first&.id
        UI.message("namespace id is #{namespace_id}")

        # GitLab uses project path with namespace (username/repo_name format)
        project_path = "#{gitlab_username}/#{repo_name}"

        begin
          new_project = gitlab.create_project(repo_name, description: repo_description, visibility: "public", namespace: gitlab_username)
        rescue Gitlab::Error::BadRequest => e
          if e.message.include?("'name' has already been taken, 'path' has already been taken, 'project_namespace.name' has already been taken")
            # search if project is active
            begin
              active_project = gitlab.project(project_path)
            rescue Gitlab::Error::NotFound
              # not found among active repos
              # search among deleted projects
              UI.message("#{active_project.name} not found")
              new_project = gitlab.create_project(repo_name, description: repo_description, visibility: "public", namespace: gitlab_username)
            else
              # project is found, here edit then delete
              edited_project = gitlab.edit_project(
                active_project.id,
                name: "#{active_project.name}-for-deletion",
                description: "project slated for deletion"
              )
              gitlab.delete_project(edited_project.id)
              UI.message("deleted #{edited_project.name}")
              new_project = gitlab.create_project(repo_name, description: repo_description, visibility: "public", namespace: gitlab_username)
            end
          else
            UI.error(e.message.to_s)
            exit
          end
        else
          UI.message("success in creating #{new_project.name}")
        end

        return {
          name_of_repository: new_project.name,
          link_to_newly_created_nightly_repo: new_project.web_url
        }
      end

      def self.add_deploy_key_to_nightly_repo(gitlab_access_token, hash_of_deploy_and_debug_keys, hash_of_repo_name_and_link_to_nightly, gitlab_username)
        # puts the deploy-key to the newly created repo automatically
        require 'gitlab'
        # Configure the client
        client = Gitlab.client(endpoint: 'https://gitlab.com/api/v4', private_token: gitlab_access_token)

        # This is project identifier in gitlab
        repo_name_and_link = "#{gitlab_username}/#{hash_of_repo_name_and_link_to_nightly[:name_of_repository]}"

        deploy_key = hash_of_deploy_and_debug_keys[:deploy_key]
        deploy_key = deploy_key.split("SSH public key to be used as deploy key:")[1].gsub("\n", "")

        # create key on gitlab
        begin
          # Add new key
          client.create_deploy_key(
            repo_name_and_link,
            "fdroid nightly deploy key for #{repo_name_and_link}",
            deploy_key,
            can_push: true
          )

          UI.message("Deploy key has been added to #{repo_name_and_link}")
        rescue Gitlab::Error::Error => e
          if e.message.include?("'deploy_key.fingerprint_sha256' has already been taken")
            UI.error("This deploy key is already in use in at #{repo_name_and_link}")
            UI.error("Generate a new keystore with the command")
            UI.error('keytool -genkeypair -alias androiddebugkey -storepass android -keypass android -keyalg RSA -keysize 2048 -keystore insert-name-here.jks -validity 100000 -noprompt')
            UI.error("Then pass insert-name-here.jks as your keystore to continue")
            UI.error("The add it to as a variable in the .env file with its complete path")
            UI.error("Run the action again")
            exit
          else
            UI.message("Unknown deploy key error")
            UI.error("Error #{e.message}")
            exit
          end
        end
      end

      def self.add_debug_keystore_as_secret_to_repo(gitlab_username, gitlab_access_token, name_of_repo, hash_of_debug_keystore_and_deploy_key)
        require "gitlab"

        client = Gitlab.client(endpoint: 'https://gitlab.com/api/v4', private_token: gitlab_access_token)

        repo_full_name = "#{gitlab_username}/#{name_of_repo}"
        debug_keystore = hash_of_debug_keystore_and_deploy_key[:debug_keystore].split("\n")[2]
        options = {
          masked: false,        # Hide value in logs
          protected: true,      # Only available on protected branches
          expanded: true
        }

        begin
          client.create_variable(
            repo_full_name,
            'DEBUG_KEYSTORE',
            debug_keystore,
            **options
          )
        rescue Gitlab::Error::Error => e
          self.update_variable_if_already_found(e, client, repo_full_name, debug_keystore, **options)
        else
          UI.message("Successfully added variable: DEBUG_KEYSTORE to #{repo_full_name}")
        end
      end

      def self.update_variable_if_already_found(e, client, repo_full_name, debug_keystore, options)
        if e.message.include?("'key' (DEBUG_KEYSTORE) has already been taken")
          begin
            client.update_variable(repo_full_name, 'DEBUG_KEYSTORE', debug_keystore, **options)
          rescue StandardError => e
            self.check_if_error_during_update(e)
          end
        end
      end

      def check_if_error_during_update(err)
        UI.error("Got this error when creating variable:DEBUG_KEYSTORE")
        UI.error(err.to_s)
        exit
      end

      def self.print_out_next_steps_to_create_nightly(hash_of_deploy_and_debug_keys, hash_of_repo_name_and_link_to_nightly)
        link_to_nightly_repo = hash_of_repo_name_and_link_to_nightly[:link_to_newly_created_nightly_repo]
        UI.message("The newly created nightly repo for your app: #{link_to_nightly_repo}")
        UI.message("Check status of your nightly job at: #{link_to_nightly_repo.sub('-nightly', '/-/jobs')}")
      end
    end
  end
end
