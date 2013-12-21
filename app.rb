require 'sinatra'
require 'sinatra/form_helpers'
require 'json'
require 'digest/sha1'
require 'pry'
require 'camlistore'

camli = Camlistore.new
puts camli.inspect
result = camli.enumerate_blobs(limit: 1)
puts result.inspect

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
	Filename = "public/blobs.json"

	def Blobserver.blobref blobcontent
		Digest::SHA1.hexdigest(blobcontent)
	end

	def Blobserver.put blobcontent
	  blobs = Blobserver.enumerate
	  blobref = Blobserver.blobref(blobcontent)
	  blobs[blobref] = blobcontent
	  Blobserver.write_all_items blobs
	  blobref
	end

	def Blobserver.get blobref
	  blobs = Blobserver.enumerate
	  blobs[blobref] || nil
	end

	def Blobserver.write_all_items blobs
		File.open(Filename,"w") do |f|
		  f.write(JSON.dump(blobs))
		end
	end

	def Blobserver.enumerate
		blobsource = {}
	  File.open(Filename, "r") do |f|
	    blobsource = JSON.load( f )
	  end
	  blobsource
	end
end

class Blobloader
	def self.get blobref
		self.load(blobref, Blobserver.get(blobref))
	end
	def self.load blobref, blobcontent
		return SchemaBlob.new(blobref, blobcontent) if SchemaBlob.valid?(blobcontent)
		return Blob.new(blobref, blobcontent) if Blob.valid?(blobcontent)
	end
end

class Blob
	attr_accessor :blobref, :blobcontent
	def initialize blobref, blobcontent
		@blobref = blobref
		@blobcontent = blobcontent
	end
	def self.valid? blobcontent
		true
	end
	def self.get blobref
		blobcontent = Blobserver.get(blobref)
		if blobcontent
			self.new(blobref, blobcontent)
		else
			nil
		end
	end
	def self.put blobcontent
		self.new(Blobserver.put(blobcontent), blobcontent)
	end
	def self.enumerate
		blobs = []
		Blobserver.enumerate.each do |blobref, blobcontent|
			blobs << self.new(blobref, blobcontent)
		end
		blobs
	end
end

class SchemaBlob < Blob
	def blobhash
		JSON.parse(@blobcontent)
	end
	def self.valid? blobcontent
		JSON.is_json?(blobcontent)
	end
	def self.find_by field, value
		blobs = self.enumerate
		blobs.select do |blob|
			blob.blobhash[field] == value
		end
		blobs
	end
end

# class Permanode < SchemaBlob
# 	def Permanode.create
# 		blobcontent = {
# 			'type' => 'permanode',
# 			'random' => rand(0..1000)
# 		}.to_json
# 		super blobcontent
# 	end
# 	def claims
# 		Claim.find_by_permanode(@blobref)
# 	end
# 	def current_claim
# 		claims.last || nil
# 	end
# 	def current_content
# 		return nil if current_claim.nil?
# 		current_claim.content
# 	end
# end

# class Claim < SchemaBlob
# 	def Claim.create permanode, content
# 		blobcontent = {
# 			'type' => 'claim',
# 			'permanode' => permanode.blobref || permanode,
# 			'content' => content.blobref || content,
# 		}.to_json
# 		super blobcontent
# 	end
# 	def Claim.find_by_permanode permanode_ref
# 		self.find_by('permanode', permanode_ref)
# 	end
# 	def content
# 		Content.get(@blobhash['content'])
# 	end
# end

get '/b/create' do
	erb :blobform
end

post '/b/create' do
	@blob = Blob.put(params[:blob]["blobcontent"])
	redirect "/b/#{@blob.blobref}"
end

get '/b/:blobref' do
	@blob = Blobloader.get(params[:blobref])
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

get '/error' do
	@title = 'Error'
	erb :error
end

get '/' do
	redirect '/b'
end