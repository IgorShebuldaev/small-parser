# frozen_string_literal: true

require 'optparse'
require 'curb'
require 'nokogiri'
require 'csv'

# The collection of data on goods for animals
class Parser
  attr_reader :link_catalog, :file_name, :links_products, :page_number, :options

  def initialize
    parse_arguments
    @link_catalog = @options[:link]
    @file_name = @options[:file]
    @links_products = []
    @page_number = 1
    parse_links
  end

  private

  def parse_arguments
    @options = {}
    OptionParser.new do |opts|
      opts.on('-l', '--link LINK', '') do |link|
        @options[:link] = link
      end

      opts.on('-f', '--file FILE', 'File name without extension.') do |file|
        @options[:file] = file + '.csv'
      end
    end.parse!
  end

  def parse_links
    puts 'Parse all product links from the catalog.'

    result = body_page
    until result.nil?
      result.xpath("//div[@class='pro_first_box ']//a/@href").to_a.each do |href|
        @links_products.push(href)
      end
      result = body_page(@page_number += 1)
    end

    puts "Collected #{links_products.size} links."
    parse_info
  end

  def body_page(page = 1)
    link = page == 1 ? Curl.get(@link_catalog) : Curl.get(@link_catalog + '?p=' + page.to_s)
    link.body.empty? ? nil : Nokogiri::HTML(link.body)
  end

  def parse_info
    products = {}
    links_img = []
    results = page_bodies

    puts 'Parse the data for each product.'
    results.each do |page|
      body_page = Nokogiri::HTML(page)
      name = body_page.xpath("//h1[@class='product_main_name']").inner_text
      weight = parse_value(body_page.xpath("//span[@class='radio_label']").to_a)
      prices = parse_value(body_page.xpath("//span[@class='price_comb']").to_a)
      link_img = body_page.at_xpath("//ul[@id='thumbs_list_frame']//a/@href")

      product, img = product_with_img(name, weight, prices, link_img)
      products = products.merge(product)
      links_img += img
    end

    write_file(products.to_enum, links_img.to_enum)
  end

  def page_bodies
    puts 'Download product pages.'
    pages = []
    Curl::Multi.get(@links_products) do |page|
      pages << page.body
    end
    pages
  end

  def parse_value(arr)
    values = []
    arr.each do |tag|
      values << tag.xpath('.').inner_text
    end
    values
  end

  def product_with_img(name, weight, prices, link_img)
    name_with_weight = []
    links_img = []
    weight.each do |w|
      name_with_weight << name + ' - ' + w
      links_img << link_img
    end
    [[name_with_weight, prices_without_euro(prices)].transpose.to_h, links_img]
  end

  def prices_without_euro(arr)
    prices = []
    arr.each do |element|
      prices << element.split(' ').first
    end
    prices
  end

  def write_file(products, links_img)
    puts 'Writing data to a file.'
    CSV.open(@file_name, 'a') do |csv|
      csv << %w[Name Price Image]
      loop do
        name_with_weight, price = products.next
        csv << [name_with_weight, price, links_img.next]
      end
    end
    puts 'Done.'
  end
end

Parser.new
