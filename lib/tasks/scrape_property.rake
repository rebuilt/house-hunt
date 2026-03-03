require 'httparty'
require 'nokogiri'

namespace :scrape do
  desc "Scrape property information from Redfin and save to a file"
  task :property, [:url] => :environment do |t, args|
    url = args[:url] || ENV['REDFIN_URL']
    
    unless url
      puts "ERROR: Please provide a URL via arguments or REDFIN_URL environment variable"
      puts "Usage: rake scrape:property[url]"
      exit 1
    end

    puts "Scraping property from: #{url}"
    
    # Fetch the page with proper headers
    response = HTTParty.get(url, {
      headers: {
        'User-Agent' => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
      },
      timeout: 30
    })

    unless response.success?
      puts "ERROR: Failed to fetch page (HTTP #{response.code})"
      exit 1
    end

    # Parse the HTML
    doc = Nokogiri::HTML(response.body)
    
    # Extract property information
    property_data = {
      url: url,
      scraped_at: Time.current.to_s,
      address: extract_address(doc),
      price: extract_price(doc),
      bedrooms: extract_bedrooms(doc),
      square_footage: extract_square_footage(doc),
      lot_size: extract_lot_size(doc),
      school_scores: extract_school_scores(doc)
    }

    # Write to file with address-based filename
    sanitized_address = property_data[:address].downcase.gsub(/[^a-z0-9]+/, '_').gsub(/^_|_$/, '')
    output_file = File.join(Rails.root, 'tmp', "#{sanitized_address}.txt")
    output_content = format_output(property_data)
    File.write(output_file, output_content)

    puts "✓ Scraped data saved to: #{output_file}"
  end

  private

  def extract_address(doc)
    # Try multiple selectors for address
    address = doc.css('[data-rf-test-id="abp-address"]').text.strip
    address = doc.css('.ds-address-block').text.strip if address.empty?
    address = doc.css('h1').text.strip if address.empty?
    address.presence || "Not found"
  end

  def extract_price(doc)
    # Try multiple selectors for price
    # price = doc.css('[data-rf-test-id="abp-price"]').text.strip
    # price = doc.css('.zestimate-value').text.strip if price.empty?
    price = doc.css('[class*="price"]').first&.children&.first&.text&.strip
    price.presence || "Not found"
  end

  def extract_bedrooms(doc)
    # Try multiple selectors for bedrooms
    value = search_in_elements(doc, %w[beds bed br])
    value.presence || "Not found"
  end

  def extract_square_footage(doc)
    # Try multiple selectors for square footage
    value = search_in_elements(doc, %w[sq.ft sqft square footage])
    value.presence || "Not found"
  end

  def extract_lot_size(doc)
    # Try multiple selectors for lot size
    value = search_in_elements(doc, %w[lot size])
    value.presence || "Not found"
  end

  def extract_school_scores(doc)
    # Extract school names and ratings cleanly
    schools = []
    text = doc.text
    
    # Simple pattern to find school info: SchoolName followed by rating on nearby lines
    text.scan(/(\w+[\w\s]*School)[^:]*?(\d+)\/10/) do |match|
      school_name = match[0].strip
      rating = match[1].to_i
      schools << "#{school_name} - #{rating}/10" if school_name.length < 100
    end

    schools.uniq.first(5).presence || ["Not found"]
  end

  def search_in_elements(doc, keywords)
    # Search for elements containing any of the keywords
    # Look for common real estate data patterns on the page
    
    keywords.each do |keyword|
      # Try data attributes first
      elem = doc.css("[data-rf-test-id*='#{keyword}']").first
      return extract_value(elem) if elem
      
      # Try class names
      elem = doc.css("[class*='#{keyword}']").first
      return extract_value(elem) if elem
      
      # Try to find in page text with flexible spacing
      text = doc.text
      # For "Lot Size", look for patterns like "Lot Size: 5,201 square feet"
      patterns = [
        Regexp.new("#{Regexp.escape(keyword)}[:\\s]+([\\d,]+[\\s\\w]*?)[\\n•]", Regexp::IGNORECASE),
        Regexp.new("#{Regexp.escape(keyword)}[:\\s]+([\\d,\\.]+\\s*(?:sq\\.?\\s*ft|sqft|square feet|sq ft))", Regexp::IGNORECASE),
        Regexp.new("#{Regexp.escape(keyword)}[:\\s]+([\\d,]+[^\\n]*?)(?::|\\n|•|$)", Regexp::IGNORECASE)
      ]
      
      patterns.each do |pattern|
        match = text.match(pattern)
        if match && match[1] && match[1].length < 100
          return match[1].strip
        end
      end
    end
    nil
  end

  def extract_value(elem)
    return nil unless elem
    # Try to get a concise value from the element
    text = elem.text.strip.split(/[\n•]/).first
    (text && text.length < 50) ? text : nil
  end

  def extract_facts(doc, keyword)
    # Generic fact extraction by looking for text containing keyword
    fact = doc.css('[class*="fact"], [data-rf-test-id*="fact"]').find do |elem|
      elem.text.downcase.include?(keyword.downcase)
    end
    
    if fact
      # Try to extract the value from the fact element
      value = fact.text.strip
      # Clean up the value to get just the relevant part
      value.split('\n').last.strip
    else
      nil
    end
  end

  def format_output(data)
    output = []
    output << "=" * 50
    output << "PROPERTY INFORMATION"
    output << "=" * 50
    output << ""
    output << "URL: #{data[:url]}"
    output << "Scraped at: #{data[:scraped_at]}"
    output << ""
    output << "Address: #{data[:address]}"
    output << "Price: #{data[:price]}"
    output << "Bedrooms: #{data[:bedrooms]}"
    output << "Square Footage: #{data[:square_footage]}"
    output << "Lot Size: #{data[:lot_size]}"
    output << ""
    output << "School Scores:"
    data[:school_scores].each do |school|
      output << "  - #{school}"
    end
    output << ""
    output << "=" * 50
    
    output.join("\n")
  end
end
