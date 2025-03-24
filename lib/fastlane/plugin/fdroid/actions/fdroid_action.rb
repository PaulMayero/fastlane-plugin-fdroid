require 'fastlane/action'
require 'gitlab'
require 'pry'
require_relative '../helper/fdroid_helper'

module Fastlane
  module Actions
    module Constants
      F_DROID_GITLAB_PROJECT_ID = "2167965"
      GITLAB_API_ENDPOINT = "https://gitlab.com/api/v4"
    end

    class FdroidAction < Action
      def self.run(params)
        UI.message("The fdroid plugin is working!")

        token = params[:gitlab_private_token]
        
        endpoint = Constants::GITLAB_API_ENDPOINT
        project_id = Constants::F_DROID_GITLAB_PROJECT_ID
        
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

        # create the issue
        issue = gitlab.create_issue(project_id, issue_title, description: issue_description)

        # print the issue details
        UI.message("RFP issue created: #{issue_title} (#{issue.web_url})")

      end

      def self.description
        "opens a PR for an app to be packaged on F-Droid"
      end

      def self.authors
        ["F-Droid"]
      end

      def self.return_value
        # If your method provides a return value, you can describe here what it does
      end

      def self.details
        # Optional:
        "more words of the above"
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(
            key: :gitlab_private_token,
            env_name: "GITLAB_PRIVATE_TOKEN",
            description: "Your GitLab Private Token with the capability of interacting with the Gitlab API.
                          Instructions of how to create it can be found here:
                          https://docs.gitlab.com/user/profile/personal_access_tokens/ ",
            optional: false,
            type: String
          )
        ]
      end

      def self.is_supported?(platform)
        # Adjust this if your plugin only works for a particular platform (iOS vs. Android, for example)
        # See: https://docs.fastlane.tools/advanced/#control-configuration-by-lane-and-by-platform
        #
        # [:ios, :mac, :android].include?(platform)
        true
      end
    end
  end
end
