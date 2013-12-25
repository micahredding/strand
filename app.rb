require 'sinatra'
require 'sinatra/form_helpers'
require 'json'
require 'digest/sha1'
require 'camlistore'
require 'rest_client'

# http://stackoverflow.com/a/9361331/3015918
module JSON
  def self.is_json?(foo)
    begin
      return false unless foo.is_a?(String)
      JSON.parse(foo).all?
    rescue JSON::ParserError
      false
    end
  end
end

class Blobserver
	@@camli = Camlistore.new

	def Blobserver.blobref blobcontent
		'sha1-' + Digest::SHA1.hexdigest(blobcontent)
	end

	def Blobserver.get blobref
	  @@camli.get(blobref)
	end

	def Blobserver.enumerate
		@@camli.enumerate_blobs.blobs
	end

	def Blobserver.create_permanode
		'./camput permanode'
	end

	def Blobserver.update_permanode blobref, attribute, value
		system "./camput attr #{blobref} #{attribute} '#{value}'"
	end

	# def Blobserver.put blobcontent
	# 	blobref = Blobserver.blobref(blobcontent)
	# 	boundary = 'randomboundaryXYZ'
	# 	content_type = "multipart/form-data; boundary=randomboundaryXYZ"
	# 	host = "localhost:3179"
	# 	upload_url = 'http://localhost:3179/bs/camli/upload'

	# 	post_body = ''
	# 	post_body << "--" + boundary + "\n"
	# 	post_body << 'Content-Disposition: form-data; name="' + blobref + '"; filename="' + blobref + '"' + "\n"
	# 	post_body << 'Content-Type: application/octet-stream' + "\n\n"
	# 	post_body << blobcontent
	# 	post_body << "\n" + '--' + boundary + '--'

	# 	response = RestClient.post upload_url, post_body, :content_type => content_type, :host => host
	# 	if JSON.parse(response)['received'][0]['blobRef'] then blobref else nil end
	# end

end

class Blob
	attr_accessor :blobref, :blobcontent
	def initialize blobref, blobcontent
		@blobref = blobref
		@blobcontent = blobcontent
	end
	def self.get blobref
		self.new(blobref, Blobserver.get(blobref))
	end
	def self.put blobcontent
		self.new(Blobserver.put(blobcontent), blobcontent)
	end
	def self.enumerate
		blobs = []
		Blobserver.enumerate.each do |blob|
			blobs << self.get(blob['blobRef'])
		end
		blobs
	end
end

class SchemaBlob < Blob
	def blobhash
		JSON.parse(@blobcontent)
	end
	def valid?
		JSON.is_json?(@blobcontent)
	end
	def self.enumerate
		blobs = super
		blobs.select do |blob|
			blob.valid?
		end
	end
	def self.find_by field, value
		blobs = self.enumerate
		blobs.select do |blob|
			blob.blobhash[field] == value
		end
	end
end

class Permanode < SchemaBlob
	def valid?
		super && blobhash['camliType'] == 'permanode'
	end

	def self.create
		blobref = Blobserver.create_permanode
		self.new(blobref, self.get(blobref))
	end

	def update attribute, value
		Blobserver.update_permanode @blobref, attribute, value
	end

	def claims
		Claim.find_by_permanode(@blobref)
	end

	def camliContent
		Blob.get(current['camliContent']).blobcontent
	end

	def current
		v = Value.new()
		v.process_claims(claims)
		v.values
	end

end


	# @begin Value class
	class Value
		attr_accessor :values

		def process_claims claims
			claims.each do |claim|
				process_claim claim.blobhash
			end
		end

		def process_claim claim
			case claim['claimType']
				when 'set-attribute'
					set_attribute claim['attribute'], claim['value']
				when 'add-attribute'
					add_attribute claim['attribute'], claim['value']
				when 'del-attribute'
					del_attribute claim['attribute']
			end
		end

		def set_attribute attribute, value
			@values ||= {}
			@values[attribute] = value
		end

		def add_attribute attribute, value
			@values ||= {}
			@values[attribute] ||= []
			@values[attribute] << value
		end

		def del_attribute attribute
			@values ||= {}
			@values.delete(attribute)
		end
	end
	# @end Value class

class Claim < SchemaBlob
	def Claim.find_by_permanode permanode_ref
		self.find_by('permaNode', permanode_ref)
	end

	def valid?
		super && blobhash['camliType'] == 'claim'
	end
end



get '/b/:blobref' do
	@blob = Blob.get(params[:blobref])
	if @blob.nil?
		redirect '/error'
	end
	@title = @blob.blobref
	erb :blob
end

get '/b' do
	@title = 'All Blobs'
	@blobs = Blob.enumerate
	erb :index
end

get '/p/create' do
	erb :form_confirm
end

post '/p/create' do
	@blob = Permanode.create
	redirect "/b/#{@blob.blobref}"
end

get '/p/:blobref/edit' do
	erb :blobform
end

post '/p/:blobref/edit' do
	@permanode = Permanode.get(params[:blobref])
	@content_blob = Blob.put(params[:blob]['blobtitle'])
	@permanode.update 'camliContent', @content_blob.blobref
	redirect "/b/#{params[:blobref]}"
end

get '/p/:blobref' do
	@permanode = Permanode.get(params[:blobref])
	if @permanode.nil?
		redirect '/error'
	end
	@title = @permanode.blobref
	erb :permanode
end

get '/p' do
	@title = 'All Permanodes'
	@blobs = Permanode.enumerate
	erb :permanode_index
end


get '/error' do
	@title = 'Error'
	erb :error
end

get '/' do
	redirect '/b'
end