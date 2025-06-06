module Fastlane
  module Actions
    module SharedValues
      FDROID_NIGHTLY_CUSTOM_VALUE = :FDROID_NIGHTLY_CUSTOM_VALUE
    end

    class FdroidNightlyAction < Action
      def self.run(params)
        # fastlane will take care of reading in the parameter and fetching the environment variable:
        #UI.message("Parameter API Token: #{params[:api_token]}")

        # sh "shellcommand ./path"

        # Actions.lane_context[SharedValues::FDROID_NIGHTLY_CUSTOM_VALUE] = "my_val"
        path_to_android_project = params[:path_to_android_project]
        github_access_token = params[:github_personal_access_token]
        github_username = get_github_username(path_to_android_project)
        debug_keystore_deploy_key_array = run_fdroid_nightly_command(path_to_android_project)
        write_out_github_yml_for_fdroid_nightly(path_to_android_project)
        github_repo_name = get_name_of_github_repo(path_to_android_project)
        x = create_online_github_repo(github_username, github_access_token, github_repo_name)
        print_out_next_steps_to_create_nightly(debug_keystore_deploy_key_array[0], debug_keystore_deploy_key_array[0], x[1])




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
                                       env_name: 'GITHUB_PERSONAL_ACCESS_TOKEN',
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
        #checks the git repo to show if github or gitlab is in use
        require 'open3'
        output, _error, status = Open3.capture3("git remote -v")
        if status.success?
          #continue execution
          if output.include?("github.com")
            return output.chomp.split(" ")[1].split("/")[0].split(":")[1]
            # runs function to process github repo
          else
            UI.Error "git service not known. Plese setup repo on gitlab or github"
            exit
          end
        end
        
        if !status.success?
          UI.error "Error getting any Git repo. Please set it up to continue"
          exit
        end
      end

      def self.run_fdroid_nightly_command(path_to_android_project)
        require 'open3'
        debug_keystore, deploy_key, status = Open3.capture3("fdroid nightly --show-secret-var")
        if status.success?
          return [debug_keystore, deploy_key]
        end

        if !status.success?
          UI.Error "fdroidserver not installed on host machine. Visit https://f-droid.org/en/docs/Installing_the_Server_and_Repo_Tools/ to sort this error"
        end
      end

      def self.write_out_github_yml_for_fdroid_nightly(path_to_android_project)
        if File.directroy?(File.join(path_to_android_project, ".github/workflows/fdroid-nightly.yml"))
          #pass for now
        else
          #create fdroid-nightly.yml
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
                    uses: actions/checkout@v2
                  - name: Gradle Wrapper Validation
                    uses: gradle/wrapper-validation-action@v1
                  - name: Set up JDK 11
                    uses: actions/setup-java@v2
                    with:
                      distribution: 'adopt'
                      java-version: 11
                  - name: Build
                    run: |
                      # use timestamp as Version Code
                      export versionCode=$(date '+%s')
                      sed -i "s,^\(\s*versionCode\)  *[0-9].*,\1 $versionCode," app/build.gradle
                      ./gradlew assembleDebug
                  - name: fdroid nightly
                    run: |
                      sudo add-apt-repository ppa:fdroid/fdroidserver
                      sudo apt-get update
                      sudo apt-get install apksigner fdroidserver --no-install-recommends
                      export DEBUG_KEYSTORE=${{ secrets.DEBUG_KEYSTORE }}
                      fdroid nightly --archive-older 10
          YAML
          File.open(github_yml, "w") do |file|
            file.write(fdroid_nightly_workflow_yaml)
          end
        end
      end

      def self.get_name_of_github_repo(path_to_android_project)
        require 'open3'
        git_remote, _error, status = Open3.capture3("git remote get-url origin")
        if status.success?
          name_of_repo = git_remote.chomp.gsub(".git","").split("/")[4]
          return name_of_repo
        else
          UI.error "Error getting any Git repo. Please set it up to continue"
          exit
        end
      end

      def self.create_online_github_repo(github_username, github_personal_access_token, name_of_repo)
        require 'octokit'

        client = Octokit::Client.new(access_token: github_personal_access_token)
        repo_name = name_of_repo + "-nightly"
        repo_description = "This will be the F-Droid nightly repo of #{name_of_repo}"
        private_repo = false

        begin
          client.repository("#{github_username}/#{repo_name}")
          UI.error "This Repo #{repo_name} already exists. Please change name and try again"
          exit
        rescue Octokit::NotFound
          repo_info = client.create_repository(repo_name, description: repo_description, private: private_repo)
          return repo_name, repo_info['html_url']
        end
      end

      #TODO: write out contents namely debug and keystore
      # and where they should be written in the repo
      def self.print_out_next_steps_to_create_nightly(deploy_key, debug_keystore, link_to_nightly_repo )
        UI.message("The deploy key is: #{deploy_key}")
        UI.message("The debug keystore is: #{debug_keystore}")
        UI.message("The newly created nightly repo is: #{link_to_nightly_repo}")
      end
    end
  end
end
