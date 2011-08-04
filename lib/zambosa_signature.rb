require 'rubygems'
require 'oauth'

class URI::HTTP
  # copied from lib/oauth/request_proxy/base.rb
  def normalized_uri
    "#{self.scheme.downcase}://#{self.host.downcase}#{(self.scheme.downcase == 'http' && self.port != 80) || (self.scheme.downcase == 'https' && self.port != 443) ? ":#{self.port}" : ""}#{(self.path && self.path != '') ? self.path : '/'}"
  end

  def site
    "#{self.scheme.downcase}://#{self.host.downcase}#{(self.scheme.downcase == 'http' && self.port != 80) || (self.scheme.downcase == 'https' && self.port != 443) ? ":#{self.port}" : ""}"
  end
end

module ZambosaSignature
  # @param url full url, i.e. http://localhost:3000/foo?x=y&a=1
  def self.signature(id, secret, url)
    u = URI.parse(url)
    options = {
      :consumer => OAuth::Consumer.new(id, secret, { :signature_method => 'hmac-sha1' }),
      :uri => u.normalized_uri # looks like http://localhost:3000/foo
    }
    r = Net::HTTP::Get.new(u.request_uri) # looks like /foo?x=y&a=1
    request_proxy = OAuth::RequestProxy.proxy(r, options)
    sig = OAuth::Signature.build(request_proxy, options)
    sig.signature
  end

  def self.signature_base_string(id, secret, url)
    u = URI.parse(url)
    r = Net::HTTP::Get.new(u.request_uri)
    consumer = OAuth::Consumer.new(id, secret)
    b = OAuth::Signature.build(r, { :consumer => consumer,
                                 :uri => u.normalized_uri 
                               })
    b.signature_base_string
  end

  def self.sign_url(id, secret, url)
    u = URI.parse(url)
    consumer = OAuth::Consumer.new(id, secret, {
                               :site => u.site,
                               :scheme => :query_string })
    req = consumer.create_signed_request(:get, u.request_uri)
    "#{u.site}#{req.path}"
  end

  def self.verify_url(id, secret, url)
    u = URI.parse(url)
    r = Net::HTTP::Get.new(u.request_uri)
    consumer = OAuth::Consumer.new(id, secret)
    OAuth::Signature.verify(r, { :consumer => consumer,
                              :uri => u.normalized_uri 
                            })
  end

end

