module Fastlane
  module Actions
    module SharedValues
      FDROID_SUBMIT_REPO_TO_DAPPER_REGISTRY_CUSTOM_VALUE = :FDROID_SUBMIT_REPO_TO_DAPPER_REGISTRY_CUSTOM_VALUE
    end

    module Constants
      DAPPER_REGISTRY_URL = "https://appiverse.io/submit/"
    end

    class FdroidSubmitRepoToDapperRegistryAction < Action
      def self.run(params)
        # fastlane will take care of reading in the parameter and fetching the environment variable:
        
        path_to_fdroid_repo_config_yml = params[:path_to_config_yml]
        appiverse_url =  Constants::DAPPER_REGISTRY_URL

        # call our methods
        repo_data = read_config_yml(path_to_fdroid_repo_config_yml)
        verified_config_content = verify_config_content(repo_data)
        appiverseio_submit(verified_config_content, appiverse_url)
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        'Enables F-Droid repo owners to submit their repos to the Dapper Registry on appiverse.io for listing'
      end

      def self.details
        # Optional:
        # this is your chance to provide a more detailed description of this action
        'You can use this action to do submit your Repo to the Dapper Registry on appiverse.io .'
      end

      def self.available_options
        # Define all options your action supports.

        # Below a few examples
        [
          FastlaneCore::ConfigItem.new(key: :path_to_config_yml,
                                       # The name of the environment variable
                                       env_name: 'PATH_TO_FDROID_REPO_CONFIG_YML',
                                       # a short description of this parameter
                                       description: 'Complete file path to the config.yml',
                                       verify_block: proc do |value|
                                         unless value && !value.empty?
                                          UI.user_error!("Couldn't find file at path '#{value}'") unless File.exist?(value)
                                         end
                                       end),
        ]
      end

      def self.authors
        ['F-Droid']
      end

      def self.is_supported?(platform)
        true
      end

      def self.read_config_yml(path_to_yaml_file)
        # method to read config.yml file found in an F-Droid repo
        require 'yaml'
        begin
          repo_data = YAML.load_file(path_to_yaml_file)
        rescue => exception
          UI.error("Something went wrong: #{exception.message}")
          raise
        else
          return repo_data 
        end
      end

      def self.verify_config_content(config_data)
        # method to ensure atleast repo_url is available in read config.yml
        if !config_data.include?("repo_url")
          UI.error "your config.yml file does not have repo_url"
          exit
        end

        if config_data["repo_url"].nil?
          UI.error "key repo_url in config.yml has no value"
          exit
        end

        return config_data
      end

      def self.appiverseio_submit(data_read_from_config, appiverse_url)
        # method to submit repo_url to appiverse.io
        require 'net/http'
        require 'uri'
        require 'nokogiri'
        require 'http-cookie'

        # Initialize cookie jar
        cookie_jar = HTTP::CookieJar.new

        # Parse URL
        uri = URI.parse(appiverse_url)

        # Create HTTP object
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == 'https')

        # Create initial GET request to fetch CSRF token
        get_request = Net::HTTP::Get.new(uri)
        response = http.request(get_request)

        # Store cookies
        response.get_fields('Set-Cookie')&.each do |cookie|
          cookie_jar.parse(cookie, uri)
        end

        # Parse CSRF token from response body
        doc = Nokogiri::HTML(response.body)
        csrf_token = doc.at_css("input[name='csrfmiddlewaretoken']")&.[]('value')

        # Prepare POST data
        post_data = {
          'csrfmiddlewaretoken' => csrf_token,
          'name' => data_read_from_config&.fetch("repo_name", nil),
          'fdroidRepoUrl' => data_read_from_config["repo_url"],
          'description' => data_read_from_config&.fetch("repo_description", nil),
          'website' => data_read_from_config&.fetch("repo_website", nil)
        }

        # Create POST request
        post_request = Net::HTTP::Post.new(uri.path)
        post_request.set_form_data(post_data)

        # Add cookies to the request
        cookie_string = cookie_jar.cookies(uri).map { |c| "#{c.name}=#{c.value}" }.join('; ')
        post_request['Cookie'] = cookie_string

        # Execute POST request
        post_response = http.request(post_request)
        UI.message("Thank you for submitting #{data_read_from_config["repo_url"]} to https://appiverse.io")
        UI.message("Your submission is under review.")
        UI.message("Depending on the outcome. It may be added or not to the Dapper registry")

      end
    end
  end
end
