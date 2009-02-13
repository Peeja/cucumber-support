# Right now, steps files each need to require this file to make
# sure it loads before they do.  Make sure we only load once.
unless defined? Cucumber::CommonNavigation

module Cucumber::CommonNavigation
  PAGES = {}
  def Page(name, path=nil, &block)
    name = case name
    when String
      name.downcase
    when Regexp
      name
    else
      raise ArugumentError, "Page only takes a String or a Regexp"
    end
    PAGES[name] = path || block
  end
  
  # Looks up the URL of a known page.  Raises a RuntimeError if
  # the named page is not found.  You can use this in your own
  # steps which refer to pages.
  # 
  #   # In steps file.
  #   Page "login", "/login"
  # 
  #   # Within a step itself.
  #   url_of_page("login")          #=> "/login"
  #   url_of_page("the login page") #=> "/login"
  #   url_of_page("tHe lOGin pAgE") #=> "/login"
  def url_of_page(full_page_name)
    page_name = canonical_page_name(full_page_name)
    path, captures = page_and_captures(page_name)

    path = case path
    when Proc
      instance_exec(*captures, &path)
    when Array
      send path[0], path[1]
    when String
      path
    else
      nil
    end
    
    raise "I don't know where #{full_page_name} is.\nAdd 'Page \"#{page_name}\", <url>' to your steps." unless path
    path
  end
  
  def page_is_kind_of_path?(full_page_name, path_to_match)
    page_name = canonical_page_name(full_page_name)
    pattern, captures = page_and_captures(page_name)
    raise "I don't know where #{full_page_name} is.\nAdd 'Page \"#{page_name}\", <url>' to your steps." unless pattern
    
    case pattern
    when Proc
      path_to_match == instance_exec(*captures, &pattern)
    when String
      path_to_match == pattern
    when Array
      route_params = ActionController::Routing::Routes.recognize_path(path_to_match)

      # This will fail if the given params don't match the ones
      # which the named route accepts.
      gen_path = send pattern[0], route_params.merge(pattern[1]) rescue nil
      
      path_to_match == gen_path
    end
  end
  
  private
  
  def page_and_captures(page_name)
    # This wants to be done with HoboSupport's #find_and_map.
    match = nil
    _, page = PAGES.find do |k, v|
      case k
      when String
        k == page_name
      when Regexp
        match = k.match page_name
      end
    end
    
    [page, (match ? match.captures : [])]
  end
  
  def canonical_page_name(full_page_name)
    if full_page_name =~ /\A(?:the|a|an) (.*) page\Z/i or
       full_page_name =~ /\A(?:the|a|an) (.*)\Z/i
      $1
    else
      full_page_name
    end.downcase
  end
end

include Cucumber::CommonNavigation


# Routing methods won't work outside of step definitions,
# so make them evaluate lazily.
def self.method_missing(id, *args)
  # Sometimes id is a string.  It goes against all reason,
  # but it seems to happen.  If we pass it to super, we
  # get complaints, so we make it a symbol first.
  id = id.to_sym
  
  # Don't resolve named routes until they're needed.  Store as
  # a symbol & params hash pair.
  if id.to_s =~ /(_url|_path)$/
    options = args.last || {}
    [id, options]
  else
    super id, *args
  end
end


Given /^I am (?:on|at) (.*)/ do |page|
  visit url_of_page(page)
end

When /^I go to (.*)/ do |page|
  visit url_of_page(page)
end

# For pages defined by a named route, matches any URL which is handled by
# that route.  For strings, the path must match exactly.  For blocks, the
# path must match whatever the block returns.
Then /^I should(?: still)? be (?:at|on) (.*)$/ do |page|
  unless page_is_kind_of_path?(page, URI(path).path)
    raise "Currently at #{path} which does not seem to be #{page}"
  end
end

Then /^I should be redirected to (.*)$/ do |page|
  Then "I should be on #{page}"
end

end # unless defined? Cucumber::CommonNavigation