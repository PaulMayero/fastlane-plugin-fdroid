module Fastlane
  module Actions
    module SharedValues
      FDROID_NIGHTLY_CUSTOM_VALUE = :FDROID_NIGHTLY_CUSTOM_VALUE
    end

    class FdroidNightlyAction < Action
      def self.run(params)
        # fastlane will take care of reading in the parameter and fetching the environment variable:
        # UI.message("Parameter API Token: #{params[:api_token]}")

        # sh "shellcommand ./path"

        # Actions.lane_context[SharedValues::FDROID_NIGHTLY_CUSTOM_VALUE] = "my_val"
        path_to_android_project = params[:path_to_android_project]
        github_access_token = params[:github_personal_access_token]
        # require 'pry'
        # require 'pry-byebug'
        # binding.pry
        path_to_android_project = File.expand_path(path_to_android_project)

        github_username = get_github_username(path_to_android_project)
        github_repo_name = get_github_reponame(path_to_android_project)

        hash_of_debug_keystore_and_deploy_key = run_fdroid_nightly_command

        path_to_fdroid_nightly_yml_file = write_out_github_yml_for_fdroid_nightly(path_to_android_project)
        add_and_commit_fdroid_nightly_yml(path_to_fdroid_nightly_yml_file)

        hash_of_repo_name_and_link_to_nightly = create_online_github_repo(github_username, github_access_token, github_repo_name)
        add_deploy_key_to_nightly_repo(github_access_token, hash_of_debug_keystore_and_deploy_key, hash_of_repo_name_and_link_to_nightly, github_username)
        add_debug_keystore_as_secret_to_repo(github_username, github_access_token, github_repo_name, hash_of_debug_keystore_and_deploy_key)
        # add_and_commit_fdroid_nightly_yml(path_to_fdroid_nightly_yml_file)
        print_out_next_steps_to_create_nightly(hash_of_debug_keystore_and_deploy_key, hash_of_repo_name_and_link_to_nightly)
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        'Create a Nightly Repo on Github to access nightly versions of your App'
      end

      def self.details
        # Optional:
        # this is your chance to provide a more detailed description of this action
        'You can use this action to do cool things...'
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
          FastlaneCore::ConfigItem.new(key: :github_personal_access_token,
                                       env_name: 'GITHUB_TOKEN',
                                       description: 'Developer Github personal access token to be used to create the Nightly Repo on Github',
                                       verify_block: proc do |value|
                                                       unless value && !value.empty?
                                                         UI.user_error("No Github Personal token found, pass using `github_personal_access_token: 'token'`")
                                                       end
                                                     end)
        ]
      end

      def self.output
        # Define the shared values you are going to provide
        # Example
        [
          ['FDROID_NIGHTLY_CUSTOM_VALUE', 'A description of what this value contains']
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

      def self.get_github_username(path_to_android_project)
        # checks if there is any git repo and returns username
        require 'rugged'
        begin
          repo = Rugged::Repository.discover(path_to_android_project)
        rescue StandardError => e
          UI.error("Error: No Git Repo found. #{e.message}")
          UI.message("Please set up Github repo then try again")
        else
          if repo.config['user.name'].nil?
            repo_url = repo.remotes['origin'].url
            github_user = repo_url.split(%r{[:/]}).reject(&:empty?)
            if repo_url.start_with?("http")
              # extract repo name from http repo
              return github_user[2]
            else
              # extract repo name from ssh repo
              return github_user[1]
            end
          else
            return repo.config['user.name']
          end
        ensure
          repo&.close
        end
      end

      def self.run_fdroid_nightly_command
        require 'open3'
        debug_keystore, deploy_key, status = Open3.capture3("fdroid nightly --show-secret-var")
        if status.success?
          return {
            debug_keystore: debug_keystore, # debug.keystore encoded for the DEBUG_KEYSTORE secret variable
            deploy_key: deploy_key # SSH Public key, used as deploy key
          }
        end

        unless status.success?
          UI.error("fdroidserver not installed on host machine. Visit https://f-droid.org/en/docs/Installing_the_Server_and_Repo_Tools/ to sort this error")
          exit
        end
      end

      def self.write_out_github_yml_for_fdroid_nightly(path_to_android_project)
        if File.directory?(File.join(path_to_android_project, ".github/workflows/fdroid-nightly.yml"))
          # pass for now
        else
          # create fdroid-nightly.yml
          require 'fileutils'
          full_path_to_github_yml_file = File.join(path_to_android_project, ".github/workflows/")
          FileUtils.mkdir_p(full_path_to_github_yml_file)
          github_yml = File.join(full_path_to_github_yml_file, 'fdroid-nightly.yml')
          fdroid_nightly_workflow_yaml = <<~YAML
            ---
            name: Publish nightly build

            on:
              push:
                branches:
                  - main

            jobs:
              nightly:
                name: Publish nightly build
                runs-on: ubuntu-latest
                environment: nightly
                steps:
                  - name: Checkout
                    uses: actions/checkout@v4
                  - name: Gradle Wrapper Validation
                    uses: gradle/wrapper-validation-action@v3
                  - name: Set up JDK 17
                    uses: actions/setup-java@v2
                    with:
                      distribution: 'adopt'
                      java-version: 17
                  - name: Build
                    run: |
                      # use timestamp as Version Code
                      export versionCode=$(date '+%s')
                      sed -i "s,^|(|s*versionCode|)  *[0-9].*,|1 $versionCode," app/build.gradle*
                      ./gradlew assembleDebug
                  - name: fdroid nightly
                    run: |
                      sudo add-apt-repository ppa:fdroid/fdroidserver
                      sudo apt-get update
                      sudo apt-get install apksigner fdroidserver --no-install-recommends
                      export DEBUG_KEYSTORE=${{ secrets.DEBUG_KEYSTORE }}
                      fdroid nightly --archive-older 10
          YAML
          File.write(github_yml, fdroid_nightly_workflow_yaml, encoding: "UTF-8")
          UI.message("F-Droid Nightly workflow is published at #{github_yml}")
          return github_yml
        end
      end

      def self.add_and_commit_fdroid_nightly_yml(path_to_yaml_file)
        require "open3"
        _output, _error, status = Open3.capture3("git add #{path_to_yaml_file} && git commit -m 'add fdroid-nightly.yml'")
        if status.success?
          UI.message("Added #{path_to_yaml_file} to git tree and success on commit")
          _output, _error, status = Open3.capture3("git push -f origin")
          if status.success?
            UI.message("pushed changes to online repo")
          else
            UI.error("Could not push changes to online repo")
            exit
          end
        else
          UI.error("Something wrong happened, try to add #{path_to_yaml_file} manually")
          exit
        end
      end

      def self.get_github_reponame(path_to_android_project)
        # returns repo name
        require 'rugged'
        begin
          repo = Rugged::Repository.discover(path_to_android_project)
        rescue StandardError => e
          UI.error("Error: No Git Repo found. #{e.message}")
          UI.message("Please set up Github repo then try again")
          exit
        else
          repo_url = repo.remotes['origin'].url
          repo_url.split(%r{[:/]})[-1].gsub(".git", "")
        ensure
          repo&.close
        end
      end

      def self.create_online_github_repo(github_username, github_personal_access_token, name_of_repo)
        require 'octokit'

        client = Octokit::Client.new(access_token: github_personal_access_token)
        repo_name = "#{name_of_repo}-nightly"
        repo_description = "This will be the F-Droid nightly repo of #{name_of_repo}"
        private_repo = false

        begin
          client.repository("#{github_username}/#{repo_name}")
          UI.error("This Repo #{repo_name} already exists. Please change name and try again")
          exit
        rescue Octokit::NotFound
          repo_info = client.create_repository(repo_name, description: repo_description, private: private_repo)
          return {
            name_of_repository: repo_name,
            link_to_newly_created_nightly_repo: repo_info['html_url']
        }
        end
      end

      def self.add_deploy_key_to_nightly_repo(github_access_token, hash_of_deploy_and_debug_keys, hash_of_repo_name_and_link_to_nightly, github_username)
        # puts the deploy-key to the newly created repo automatically
        require 'octokit'
        client = Octokit::Client.new(
          access_token: github_access_token
        )

        repo_name_and_link = "#{github_username}/#{hash_of_repo_name_and_link_to_nightly[:name_of_repository]}"

        deploy_key = hash_of_deploy_and_debug_keys[:deploy_key]
        deploy_key = deploy_key.split("SSH public key to be used as deploy key:")[1].gsub("\n", "")

        key_details = {
          title: "fdroid nightly deploy key for #{repo_name_and_link}",
          key: deploy_key,
          read_only: false
        }

        begin
          client.add_deploy_key(
            repo_name_and_link,
            key_details[:title],
            key_details[:key],
            read_only: key_details[:read_only]
          )
          UI.message("Deploy key has been added to #{repo_name_and_link}")
        rescue Octokit::UnprocessableEntity => e
          if e.message.include?("key is already in use")
            UI.error("This deploy key is already in use")
            exit
          else
            UI.error("Error #{e.message}")
          end
        rescue Octokit::Error => e
          UI.error("Github  APi Error #{e.message}")
          exit
        end
      end

      def self.add_debug_keystore_as_secret_to_repo(github_username, github_personal_access_token, name_of_repo, hash_of_debug_keystore_and_deploy_key)
        require 'octokit'
        require 'rbnacl'
        require 'base64'

        client = Octokit::Client.new(access_token: github_personal_access_token)
        repo_full_name = "#{github_username}/#{name_of_repo}"
        begin
          github_key = client.get_actions_public_key(repo_full_name)
          key_id = github_key[:key_id]
          public_key = RbNaCl::PublicKey.new(Base64.decode64(github_key[:key])) # rubocop:disable Require/MissingRequireStatement
        rescue Exception => e # rubocop:disable Lint/RescueException
          UI.error("Error: #{e.message}")
          exit
        end

        box = RbNaCl::Boxes::Sealed.from_public_key(public_key) # rubocop:disable Require/MissingRequireStatement
        debug_keystore = hash_of_debug_keystore_and_deploy_key[:debug_keystore].split("\n")[2]
        UI.message("the debug keystore is #{debug_keystore}")
        encrypted_secret = box.encrypt(debug_keystore)
        UI.message("the encrypted debug keystore is #{encrypted_secret}")

        # create or update the secret
        begin
          client.create_or_update_actions_secret(
            repo_full_name,
            'DEBUG_KEYSTORE',
            {
              encrypted_value: encrypted_secret,
              key_id: key_id
            }
          )
        rescue Exception => e # rubocop:disable Lint/RescueException
          UI.error("Error: #{e.message}")
          exit
        else
          UI.message("DEBUG_KEYSTORE has been added to #{repo_full_name} as a secret key")
        end
      end

      # TODO: write out contents namely debug and keystore
      # and where they should be written in the repo
      def self.print_out_next_steps_to_create_nightly(hash_of_deploy_and_debug_keys, hash_of_repo_name_and_link_to_nightly)
        deploy_key = hash_of_deploy_and_debug_keys[:deploy_key]
        debug_keystore = hash_of_deploy_and_debug_keys[:debug_keystore]
        link_to_nightly_repo = hash_of_repo_name_and_link_to_nightly[:link_to_newly_created_nightly_repo]
        UI.message("encoded for the DEBUG_KEYSTORE secret variable: #{debug_keystore}")
        UI.message("SSH public key to be used as deploy key: #{deploy_key}")
        UI.message("The newly created nightly repo for your app: #{link_to_nightly_repo}")
      end
    end
  end
end
