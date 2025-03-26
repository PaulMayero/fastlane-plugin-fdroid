module Fastlane
  module Actions
    module Constants
      F_DROID_GITLAB_PROJECT_ID = "2167965"
      GITLAB_API_ENDPOINT = "https://gitlab.com/api/v4"
    end

    class FdroidRequestAppForPackagingAction < Action
      def self.run(params)
        token = params[:gitlab_private_token]

        endpoint = Constants::GITLAB_API_ENDPOINT
        project_id = Constants::F_DROID_GITLAB_PROJECT_ID

        # call method
        request_app_on_fdroid(token, endpoint, project_id)
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        "Opens an issue for an app to be packaged on [F-Droid](https://f-droid.org/en/)"
      end

      def self.details
        # Optional:
        # this is your chance to provide a more detailed description of this action
        'You can use this action to request your app to be packaged by the F-Droid team and have it
        available on the F-Droid app store'
      end

      def self.available_options
        # Define all options your action supports.

        # Below a few examples
        [
          FastlaneCore::ConfigItem.new(
            key: :gitlab_private_token,
            env_name: "GITLAB_PRIVATE_TOKEN",
            description: "Your GitLab Private Token with the capability of interacting with the Gitlab API. Instructions of how to create it can be found here: https://docs.gitlab.com/user/profile/personal_access_tokens/ ",
            verify_block: proc do |value|
              unless value && !value.empty?
                UI.user_error!("No Gitlab token given, pass using `gitlab_private_token: 'token'`")
              end
            end)
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

      def self.request_app_on_fdroid(token, endpoint, project_id)
        # Opens an issue on the F-Droid gitlab with details of app
        require 'gitlab'

        gitlab = Gitlab.client(
          endpoint: endpoint,
          private_token: token,
        )

        issue_title = UI.input("Enter package name of app: ")

        source_code_link= UI.input("Enter link to the source code: ")

        similar_app_link = UI.input("Enter link of app on any other App store: ")

        license = UI.input("Add license of app: ")

        category  = UI.input("What category does this app belong to: ")

        summary  = UI.input("Summary of the app: ")

        description  = UI.input("Long description of the app: ")


        issue_description = <<~TEMPLATE
        * [ ] The app complies with the [inclusion criteria](https://f-droid.org/wiki/page/Inclusion_Policy)
        * [ ] The app is not already listed in the repo or issue tracker.
        * [ ] The original app author has been notified (and does not oppose the inclusion).
        * [ ] [Donated](https://f-droid.org/donate/) to support the maintenance of this app in F-Droid.

        ---------------------

        ### Link to the source code:
        #{source_code_link}

        ### Link to app in another app store:
        #{similar_app_link}

        ### License used:
        #{license}

        ### Category:
        #{category}

        ### Summary:
        #{summary}

        ### Description:
        #{description}

        TEMPLATE

        begin
          # create the issue
          issue = gitlab.create_issue(project_id, issue_title, description: issue_description)
        rescue => exception
          UI.error("Error: #{exception.message}")
          raise
        else
          # print the issue details
          UI.message("RFP issue created: #{issue_title} (#{issue.web_url})")
        end

      end
    end
  end
end
