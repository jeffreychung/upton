# encoding: UTF-8

# *Upton* is a framework for easy web-scraping with a useful debug mode 
# that doesn't hammer your target's servers. It does the repetitive parts of 
# writing scrapers, so you only have to write the unique parts for each site.
#
# Upton operates on the theory that, for most scraping projects, you need to
# scrape two types of pages:
# 
# 1. Index pages, which list instance pages. For example, a job search 
#     site's search page or a newspaper's homepage.
# 2. Instance pages, which represent the goal of your scraping, e.g.
#     job listings or news articles.

module Upton

  # Upton::Scraper can be used as-is for basic use-cases, or can be subclassed
  # in more complicated cases; e.g. +MyScraper < Upton::Scraper+
  class Scraper

    attr_accessor :verbose, :debug, :nice_sleep_time, :stash_folder

    # == Basic use-case methods.

    # This is the main user-facing method for a basic scraper.
    # Call +scrape+ with a block; this block will be called on 
    # the text of each instance page, (and optionally, its URL and its index
    # in the list of instance URLs returned by +get_index+).
    def scrape &blk
      self.scrape_from_list(self.get_index, blk)
    end


    # == Configuration Options

    # +index_url+: The URL of the page containing the list of instances.
    # +selector+: The XPath or CSS that specifies the anchor elements within 
    # the page.
    # +selector_method+: +:xpath+ or +:css+. By default, +:xpath+.
    #
    # These options are a shortcut. If you plant to override +get_index+, you
    # do not need to set them.
    def initialize(index_url="", selector="", selector_method=:xpath)
      @index_url = index_url
      @index_selector = selector
      @index_selector_method = selector_method

      # If true, then Upton prints information about when it gets
      # files from the internet and when it gets them from its stash.
      @verbose = false

      # If true, then Upton fetches each instance page only once
      # future requests for that file are responded to with the locally stashed
      # version.
      # You may want to set @debug to false for production (but maybe not).
      # You can also control stashing behavior on a per-call basis with the
      # optional second argument to get_page, if, for instance, you want to 
      # stash certain instance pages, e.g. based on their modification date.
      @debug = true
      # Index debug does the same, but for index pages.
      @index_debug = false

      # In order to not hammer servers, Upton waits for, by default, 30  
      # seconds between requests to the remote server.
      @nice_sleep_time = 30 #seconds

      # Folder name for stashes, if you want them to be stored somewhere else,
      # e.g. under /tmp.
      @stash_folder = "stashes"
      unless Dir.exists?(@stash_folder)
        Dir.mkdir(@stash_folder)
      end
    end



    # If instance pages are paginated, <b>you must override</b> 
    # this method to return the next URL, given the current URL and its index.
    #
    # If instance pages aren't paginated, there's no need to override this.
    #
    # Return URLs that are empty strings are ignored (and recursion stops.)
    # e.g. next_instance_page_url("http://whatever.com/article/upton-sinclairs-the-jungle?page=1", 2)
    # ought to return "http://whatever.com/article/upton-sinclairs-the-jungle?page=2"
    def next_instance_page_url(url, index)
      ""
    end

    # If index pages are paginated, <b>you must override</b>
    # this method to return the next URL, given the current URL and its index.
    #
    # If index pages aren't paginated, there's no need to override this.
    #
    # Return URLs that are empty strings are ignored (and recursion stops.)
    # e.g. +next_index_page_url("http://whatever.com/articles?page=1", 2)+
    # ought to return "http://whatever.com/articles?page=2"
    def next_index_page_url(url, index)
      ""
    end


    protected


    #Handles getting pages with RestClient or getting them from the local stash
    def get_page(url, stash=false)
      return "" if url.empty?

      #the filename for each stashed version is a cleaned version of the URL.
      if stash && File.exists?( File.join(@stash_folder, url.gsub(/[^A-Za-z0-9\-]/, "") ) )
        puts "usin' a stashed copy of " + url if @verbose
        resp = open( File.join(@stash_folder, url.gsub(/[^A-Za-z0-9\-]/, "")), 'r:UTF-8').read
      else
        begin
          puts "getting " + url if @verbose
          sleep @nice_sleep_time
          resp = RestClient.get(url, {:accept=> "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"})
        rescue RestClient::ResourceNotFound
          resp = ""
        rescue RestClient::InternalServerError
          resp = ""
        end
        if stash
          puts "I just stashed (#{resp.code if resp.respond_to?(:code)}): #{url}" if @verbose
          open( File.join(@stash_folder, url.gsub(/[^A-Za-z0-9\-]/, "") ), 'w:UTF-8'){|f| f.write(resp.encode("UTF-8", :invalid => :replace, :undef => :replace ))}
        end
      end
      resp
    end

    # Return a list of URLs for the instances you want to scrape.
    # This can optionally be overridden if, for example, the list of instances
    # comes from an API.
    def get_index
      parse_index(get_index_pages(@index_url, 1), @index_selector, @index_selector_method)
    end

    # Using the XPath or CSS selector and selector_method that uniquely locates
    # the links in the index, return those links as strings.
    def parse_index(text, selector, selector_method=:xpath)
      Nokogiri::HTML(text).send(selector_method, selector).to_a.map{|l| l["href"] }
    end

    # Returns the concatenated output of each member of a paginated index,
    # e.g. a site listing links with 2+ pages.
    def get_index_pages(url, index)
      resp = self.get_page(url, @index_debug)
      if !resp.empty? 
        next_url = self.next_index_page_url(url, index + 1)
        unless next_url == url
          next_resp = self.get_index_pages(next_url, index + 1).to_s 
          resp += next_resp
        end
      end
      resp
    end

    # Returns the concatenated output of each member of a paginated instance,
    # e.g. a news article with 2 pages.
    def get_instance(url, index=0)
      resp = self.get_page(url, @debug)
      if !resp.empty? 
        next_url = self.next_instance_page_url(url, index + 1)
        unless next_url == url
          next_resp = self.get_instance(next_url, index + 1).to_s 
          resp += next_resp
        end
      end
      resp
    end

    # Just a helper for +scrape+.
    def scrape_from_list(list, blk)
      puts "Scraping #{list.size} instances" if @verbose
      list.each_with_index.map do |instance_url, index|
        blk.call(get_instance(instance_url), instance_url, index)
      end
    end

    # it's often useful to have this slug method for uniquely (almost certainly) identifying pages.
    def slug(url)
      url.split("/")[-1].gsub(/\?.*/, "").gsub(/.html.*/, "")
    end

  end
end