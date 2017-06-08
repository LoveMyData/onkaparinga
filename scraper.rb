require 'scraperwiki'
require 'mechanize'

def is_valid_year(date_str, min=2004, max=DateTime.now.year)
  if ( date_str.scan(/^(\d)+$/) )
    if ( (min..max).include?(date_str.to_i) )
      return true
    end
  end
  return false
end

unless ( is_valid_year(ENV['MORPH_PERIOD'].to_s) )
  ENV['MORPH_PERIOD'] = DateTime.now.year.to_s
end
puts "Getting data in year `" + ENV['MORPH_PERIOD'].to_s + "`, changable via MORPH_PERIOD environment"

base_url = "http://pathway.onkaparinga.sa.gov.au/ePathway/Production/Web/"
comment_url = "mailto:mail@onkaparinga.sa.gov.au"

# get the right cookies
agent = Mechanize.new
agent.user_agent_alias = 'Mac Safari'
page = agent.get base_url + "default.aspx"

# get to the page I can enter DA search
page = agent.get base_url + "GeneralEnquiry/EnquiryLists.aspx?ModuleCode=LAP"

# local DB lookup if DB exist and find out what is the maxDA number
sequences = {1=>1, 6=>6000, 8=>8000};
sql = "select council_reference from data where `council_reference` like '%/#{ENV['MORPH_PERIOD']}'"
results = ScraperWiki.sqliteexecute(sql) rescue false

if ( results )
  results.each do |result|
    maxDA = result['council_reference'].gsub!("/#{ENV['MORPH_PERIOD']}", '')
    case maxDA.to_i
      when (6000..7999)
        if maxDA.to_i > sequences[6]
          sequences[6] = maxDA.to_i
        end
      when (8000..9999)
        if maxDA.to_i > sequences[8]
          sequences[8] = maxDA.to_i
        end
      else
        if maxDA.to_i > sequences[1]
          sequences[1] = maxDA.to_i
        end
    end
  end
end

sequences.each do |index, sequence|
  i        = sequence
  error    = 0
  continue = true

  while continue do
    form = page.form
    form.field_with(:name=>'ctl00$MainBodyContent$mGeneralEnquirySearchControl$mTabControl$ctl04$mFormattedNumberTextBox').value = i.to_s + '/' + ENV['MORPH_PERIOD'].to_s
    button = form.button_with(:value => "Search")
    list = form.click_button(button)

    table = list.search("table.ContentPanel")
    unless ( table.empty? )
      error  = 0
      tr     = table.search("tr.ContentPanel")

      record = {
        'council_reference' => tr.search('a').inner_text,
        'address'           => tr.search('span')[3].inner_text,
        'description'       => tr.search('span')[2].inner_text.gsub("\n", '. ').squeeze(' '),
        'info_url'          => base_url + 'GeneralEnquiry/' + tr.search('a')[0]['href'],
        'comment_url'       => comment_url,
        'date_scraped'      => Date.today.to_s,
        'date_received'     => Date.parse(tr.search('span')[1].inner_text).to_s,
      }

      if (ScraperWiki.select("* from data where `council_reference`='#{record['council_reference']}'").empty? rescue true)
        puts "Saving record " + record['council_reference'] + ", " + record['address']
#         puts record
        ScraperWiki.save_sqlite(['council_reference'], record)
      else
        puts 'Skipping already saved record ' + record['council_reference']
      end
    else
      error += 1
    end

    # increase i value and scan the next DA
    i += 1
    if error == 10
      continue = false
    end
  end
end
