require 'sinatra'
require 'sinatra/form_helpers'
require 'json'
require 'digest/sha1'
require 'camlistore'
require 'rest_client'
require 'open3'

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
		if blobref.nil?
			return nil
		end
		puts blobref
	  @@camli.get(blobref)
	end
	def Blobserver.enumerate
		@@camli.enumerate_blobs.blobs
	end
	def Blobserver.create_permanode
		`./camput permanode`
	end
	# def Blobserver.create_share blobref
	# 	system "./camput share --transitive '#{blobref}'"
	# end
	def Blobserver.update_permanode blobref, attribute, value
		blobref.delete!("\n")
		attribute.delete!("\n")
		value.delete!("\n")
		`./camput attr #{blobref} #{attribute} #{value}`
	end
	def Blobserver.put blobcontent
		output = nil
		cmd = "./camput blob - "
		Open3.popen3(cmd) do |stdin, stdout, stderr|
			stdin.puts blobcontent
			stdin.close
			stdout.each_line do |line|
				output = line
			end
		end
		output
	end
end

class Blob
	def initialize blobref, blobcontent=nil
		@blobref = blobref
		@blobcontent = blobcontent
	end
	def blobref
		@blobref
	end
	def blobcontent
		if @blobcontent.nil?
			@blobcontent = Blobserver.get(blobref)
		end
		@blobcontent
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
			blobs << self.new(blob['blobRef'])
		end
		blobs
	end
end

class SchemaBlob < Blob
	def blobhash
		if @blobhash.nil?
			if JSON.is_json?(blobcontent)
				@blobhash = JSON.parse(blobcontent)
			else
				@blobhash = {}
			end
		end
		@blobhash
	end
	def valid?
		JSON.is_json?(blobcontent)
	end
	def self.enumerate
		super.select do |blob|
			blob.valid?
		end
	end
	def self.find_by field, value
		self.enumerate.select do |blob|
			blob.blobhash[field] == value
		end
	end
end

class Claim < SchemaBlob
	def type() blobhash['claimType'] end
	def attribute() blobhash['attribute'] end
	def value()	blobhash['value'] end
	def date() DateTime.parse(blobhash['claimDate']) end

	def valid?
		super && blobhash['camliType'] == 'claim'
	end
	def self.enumerate
		super.sort_by! { |blob| blob.blobhash["claimDate"] }
	end
	def self.find_by_permanode permanode_ref
		self.find_by('permaNode', permanode_ref)
	end
	# def self.process_claims claims
	# 	values = {}
	# 	claims.each do |claim|
	# 		case claim.type
	# 			when 'set-attribute'
	# 				values[claim.attribute] = claim.value
	# 			when 'add-attribute'
	# 				values[claim.attribute] ||= []
	# 				values[claim.attribute] << claim.value
	# 			when 'del-attribute'
	# 				values.delete(claim.attribute)
	# 		end
	# 	end
	# 	values
	# end
end

class Permanode < SchemaBlob
	def self.create
		self.new(Blobserver.create_permanode)
	end
	def valid?
		super && blobhash['camliType'] == 'permanode'
	end
	def update attribute, value
		Blobserver.update_permanode blobref, attribute, value
	end
	def claims
		if @claims.nil?
			@claims = Claim.find_by_permanode(blobref)
			if @claims.nil?
				@claims = []
			end
		end
		@claims
	end
	def get_attribute attribute
		if @values.nil?
			@values = {}
		end
		if !@values[attribute].nil?
			return @values[attribute]
		end
		claims.each do |claim|
			if claim.attribute == attribute
				case claim.type
					when 'set-attribute'
						@values[attribute] = claim.value
					when 'add-attribute'
						@values[attribute] ||= []
						@values[attribute] << claim.value
					when 'del-attribute'
						@values.delete(attribute)
				end
			end
		end
		if !@values[attribute].nil?
			return @values[attribute]
		else
			return nil
		end
	end
end

class Node < Permanode
	def current
		NodeRevision.new(self, 100)
	end
	def revision version
		NodeRevision.new(self, version)
	end
	def revisions
		r = []
		claims.each_with_index do |claim, index|
			r << NodeRevision.new(self, index)
		end
		r
	end
	def set_title title
		update 'title', title
	end
	def set_content content
		blobcontent = content.to_json
		blobref = Blobserver.put(blobcontent)
		update 'camliContent', blobref
	end
	def time
		current.time
	end
	def title
		current.title
	end
	def body
		current.body
	end
end

class Content < SchemaBlob
	def title
		blobhash['title'] || 'Blank'
	end
	def body
		blobhash['body'] || 'Blank'
	end
end

class NodeRevision
	attr_accessor :node, :version
	def initialize node, version
		@node = node
		@version = version
	end
	def claims
	  if @claims.nil?
			if @node.claims && @node.claims.length > 0
				@claims = @node.claims.slice(0, @version + 1)
			else
				@claims = []
			end
		end
		@claims
	end
	# def values
		# @values = Claim.process_claims(claims) if @values.nil?
	# end
	def content
		@content = Content.new(@node.get_attribute('camliContent')) if @content.nil?
	end
	def claim
		claims.last
	end
	def date
		if claims && claims.length > 0
			claims.last.date
		else
			DateTime.new
		end
	end
	def time
		date.to_time
	end
	def title
		@node.blobref || content.title
	end
	def body
		content.body
	end
end


#################
# @begin Routes #
#################

get '/node/create' do
	@title = 'Create New Entry'
	erb :form
end

post '/node/create' do
	@node = Node.create
	if @node
		@node.set_content(params[:content])
		redirect "/node/#{@node.blobref}"
	else
		redirect "/error"
	end
end

get '/node/:node_ref' do
	@node = Node.get(params[:node_ref])
	if @node.nil?
		redirect '/error'
	end
	@title = @node.title || @node.blobref
	erb :node
end

get '/node/:node_ref/revisions' do
	@node = Node.get(params[:node_ref])
	if @node.nil?
		redirect '/error'
	end
	@title = 'Revisions for ' + @node.title || @node.blobref
	erb :node_revisions
end

get '/node/:node_ref/edit' do
	@node = Node.get(params[:node_ref])
	if @node.nil?
		redirect '/error'
	end
	@title = 'Edit Node'
	erb :form
end

post '/node/:node_ref/edit' do
	@node = Node.get(params[:node_ref])
	if @node.nil?
		redirect '/error'
	end
	@node.set_content(params[:content])
	redirect "/node/#{params[:node_ref]}"
end

get '/node/:node_ref/:num' do
	@node = Node.get(params[:node_ref])
	@revision = @node.revision(params[:num].to_i)
	@title = @revision.title
	erb :node_revision
end

get '/chronicle' do
	@title = 'Timeline'
	@blobs = Claim.enumerate
	erb :chronicle_index
end

get '/error' do
	@title = 'Error'
	erb :error
end

get '/' do
	@title = 'All Entries'
	@nodes = Node.enumerate
	erb :index
end


get '/permanode' do
	redirect '/'
end
get '/node' do
	redirect '/'
end

#################
# @end Routes   #
#################
