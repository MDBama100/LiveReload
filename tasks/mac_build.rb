

class MacBuildTasks
  include Rake::DSL

  def initialize prefix, options
    @version_tasks = options[:version_tasks]
    @bundle_name   = options[:bundle_name]
    @zip_base_name = options[:zip_base_name]
    @tag_prefix    = options[:tag_prefix]
    @channel       = options[:channel]
    @target        = options[:target]

    desc "Upload the current version's build to S3"
    task "#{prefix}:upload" do
      suffix = @version_tasks.short_version
      zip_name = "#{@zip_base_name}-#{suffix}.zip"
      zip_path_in_builds = File.join(BUILDS_DIR, zip_name)

      sh 's3cmd', '-P', 'put', zip_path_in_builds, "s3://#{S3_BUCKET}/#{zip_name}"
      puts "http://#{S3_BUCKET}/#{zip_name}"
      puts "https://s3.amazonaws.com/#{S3_BUCKET}/#{zip_name}"
    end

    desc "Add the current version into the web site's versions_mac.yml"
    task "#{prefix}:publish" do |t, args|
      suffix = @version_tasks.short_version
      zip_name = "#{@zip_base_name}-#{suffix}.zip"
      date = Time.new.strftime('%Y-%m-%d')
      versions_file = File.join(SITE_DIR, '_data/versions_mac.yml')
      url = "https://s3.amazonaws.com/#{S3_BUCKET}/#{zip_name}"

      require 'net/http'
      require 'uri'
      uri = URI(url)
      file_size = nil
      puts "Getting the size of #{url}..."
      Net::HTTP.start(uri.host, uri.port, :use_ssl => (uri.scheme == 'https')) do |http|
        response = http.request_head(url)
        file_size = response['content-length'].to_i
      end
      
      snippet = <<-END
- version: "#{suffix}"
  date: #{date}
  channels:
    production: no
    #{@channel}: yes
  url: "https://s3.amazonaws.com/#{S3_BUCKET}/#{zip_name}"
  file_size: #{file_size}
  release_notes:
    - title: TODO
      details: TODO
    END

      content = snippet + "\n" + File.read(versions_file)
      File.open(versions_file, 'w') { |f| f.write content } 
      
      sh 'subl', versions_file

      puts
      puts "To publish the beta site:"
      puts
      puts "    cd #{File.expand_path(SITE_DIR).sub(ENV['HOME'], '~')}"
      puts "    jekyll serve"
      puts "    open http://0.0.0.0:4000/beta/"
      puts "    s3_website ..."
      puts
    end

    desc "Build and zip using the current version number"
    task "#{prefix}:build" do |t, args|
      suffix = @version_tasks.short_version

      zip_name = "#{@zip_base_name}-#{suffix}.zip"
      zip_path = File.join(XCODE_RELEASE_DIR, zip_name)
      zip_path_in_builds = File.join(BUILDS_DIR, zip_name)
      mac_bundle_path = File.join(XCODE_RELEASE_DIR, @bundle_name)

      rm_f zip_path
      rm_rf @bundle_name

      Dir.chdir MAC_SRC do
        sh 'xcodebuild clean'
        sh 'xcodebuild', '-target', @target
      end
      Dir.chdir XCODE_RELEASE_DIR do
        rm_rf zip_name
        sh 'zip', '-9rXy', zip_name, @bundle_name
      end

      mkdir_p File.dirname(zip_path_in_builds)
      cp zip_path, zip_path_in_builds

      Dir.chdir BUILDS_DIR do
        rm_rf @bundle_name
        sh 'unzip', '-q', zip_name

        puts
        puts "Checking code signature after unzipping."
        sh 'spctl', '-a', @bundle_name
      end

      sh 'open', '-R', zip_path_in_builds
    end

    desc "Tag using the current version number"
    task "#{prefix}:tag" do |t, args|
      suffix_for_tag = @version_tasks.short_version
      tag = "#{@tag_prefix}#{suffix_for_tag}"
      sh 'git', 'tag', '-f', tag

      Dir.chdir 'LiveReload/Compilers' do
        sh 'git', 'tag', '-f', tag
        sh 'git', 'push', '--tags'
      end

      sh 'git', 'push', '--tags'
    end
  end

private

end
