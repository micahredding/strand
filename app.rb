require 'sinatra'
require 'sinatra/form_helpers'
require 'json'
require 'digest/sha1'
require 'camlistore'
require 'open3'
require 'faraday'
require 'faraday_middleware'

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
	@@connection = Faraday.new
	@@root_url = 'http://localhost:3179'
	@@host = 'localhost:3179'

	# http://godoc.org/camlistore.org/pkg/search#SortType
  # UnspecifiedSort   = 0
  # LastModifiedDesc  = 1
  # LastModifiedAsc   = 2
  # CreatedDesc       = 3
  # CreatedAsc        = 4

	def Blobserver.init
		response = Faraday.get @@root_url, {}, :accept => 'text/x-camli-configuration'
		if response.status == 200
			if JSON.is_json?(response.body)
				info = JSON.parse(response.body)
				# puts info
				@@search_root = info['searchRoot']
				@@blob_root = info['blobRoot']
			end
		end
	end

	def Blobserver.blobref blobcontent
		'sha1-' + Digest::SHA1.hexdigest(blobcontent)
	end

	def Blobserver.get blobref
	  @@camli.get(blobref)
	 #  get_url = @@root_url + @@blob_root + 'camli/' + blobref
	 #  response = Faraday.get get_url
		# if response.status == 200
		# 	return response.body
		# end
	end

	def Blobserver.put blobcontent
		# output = nil
		# cmd = "./camput blob - "
		# Open3.popen3(cmd) do |stdin, stdout, stderr|
		# 	stdin.puts blobcontent
		# 	stdin.close
		# 	stdout.each_line do |line|
		# 		output = line
		# 	end
		# end
		# output

		blobref = Blobserver.blobref(blobcontent)
    content_type = "multipart/form-data; boundary=randomboundaryXYZ"
    upload_url = @@root_url + @@blob_root + 'camli/upload'
    boundary = 'randomboundaryXYZ'

    post_body = ''
    post_body << "--" + boundary + "\n"
    post_body << 'Content-Disposition: form-data; name="' + blobref + '"; filename="' + blobref + '"' + "\n"
    post_body << 'Content-Type: application/octet-stream' + "\n\n"
    post_body << blobcontent
    post_body << "\n" + '--' + boundary + '--'

		response = Faraday.post upload_url, post_body, :content_type => content_type, :host => @@host
		if response.status == 200
			if JSON.is_json?(response.body)
				results = JSON.parse(response.body)
				if !results.nil? && !results['received'].nil?
					blobref
				end
			end
		end
	end

	def Blobserver.describe blobref
		# at = 2012-11-02T09:35:03-00:00
	  url = @@root_url + @@search_root + 'camli/search/describe'
		response = Faraday.get url, {'blobref' => blobref}
		if response.status == 200
			if JSON.is_json?(response.body)
				results = JSON.parse(response.body)
				if !results.nil? && !results['meta'].nil? && !results['meta'][blobref].nil?
					return results['meta'][blobref]
				end
			end
		end
		{}
	end

	def Blobserver.search query
		query = query.to_json if query.is_a?(Hash)
		url = @@root_url + @@search_root + 'camli/search/query'
		response = Faraday.post url, query
		if response.status == 200
			if JSON.is_json?(response.body)
				results = JSON.parse(response.body)
				if !results.nil? && !results['blobs'].nil?
					return results['blobs']
				end
			end
		end
		[]
	end

	def Blobserver.create_permanode
		`./camput permanode`
	end

	def Blobserver.update_permanode blobref, attribute, value
		blobref.delete!("\n")
		attribute.delete!("\n")
		value.delete!("\n")
		`./camput attr #{blobref} #{attribute} '#{value}'`
	end

	def Blobserver.enumerate_type type
		Blobserver.search({"constraint" => {"camliType" => type}})
	end

	def Blobserver.find_permanode_by attribute, value
		Blobserver.search({
			"constraint" => {
				"camliType" => "permanode",
				"permanode" => {
					"attr" => attribute,
					"value" => value
				}
			}
		})
	end

	Blobserver.init
end


class Permanode
	def initialize blobref, blobcontent=nil
		@blobref = blobref
		@blobcontent = blobcontent
	end

	def blobref
		@blobref
	end

	def blobcontent
		@blobcontent = Blobserver.get(blobref) if @blobcontent.nil?
		@blobcontent
	end

	def blobhash
		@blobhash = JSON.parse(blobcontent) if @blobhash.nil?
		@blobhash
	end

	def description
		@description = Blobserver.describe(@blobref) if @description.nil?
		@description
	end

	def set_attribute attribute, value
		Blobserver.update_permanode blobref, attribute, value
	end

	def get_attribute attribute
		return nil if description.nil? || description['permanode'].nil? || description['permanode']['attr'].nil? || description['permanode']['attr'][attribute].nil? || description['permanode']['attr'][attribute].first.nil?
		description['permanode']['attr'][attribute].first
	end

	def get_modtime
		return Time.new if description.nil? || description['permanode'].nil? || description['permanode']['modtime'].nil?
		DateTime.parse(description['permanode']['modtime']).to_time
	end

	def get_claims
		claims = Blobserver.enumerate_type('claim').collect! do |blob|
			blobcontent = Blobserver.get(blob['blob'])
			if JSON.is_json?(blobcontent)
				JSON.parse(blobcontent)
			else
				{}
			end
		end
		claims.select do |blob|
			blob['permaNode'] == blobref
		end
	end

	def self.create
		self.new(Blobserver.create_permanode)
	end

	def self.get blobref
		self.new(blobref, Blobserver.get(blobref))
	end

	def self.enumerate
		Blobserver.enumerate_type('permanode').collect! do |blob|
			self.new(blob['blob'])
		end
	end

end

class Node < Permanode
	def set_title title
		set_attribute 'title', title
	end
	def set_content content
		blobref = Blobserver.put(content.to_json)
		set_attribute 'camliContent', blobref
	end

	def time
		get_modtime
	end

	def revision time
		NodeRevision.new(self, time)
	end

	def current
		NodeRevision.new(self, 0)
	end

	def title
		current.title
	end

	def content
		current.content
	end

end

class NodeRevision
	def initialize node, time
		@node = node
		@time = time
	end

	def title
		@node.get_attribute('title')
	end

	def content
		if @content.nil?
			@content = {}
			sha = @node.get_attribute('camliContent')
			if sha
				@content = Blobserver.get(sha)
				if JSON.is_json?(@content)
					@content = JSON.parse(@content)
				end
			end
		end
		@content
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
		@node.set_title(params[:content]["title"])
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

# get '/b/:blob_ref' do
# 	@blobref = params[:blob_ref]
# 	@blobcontent = Blobserver.get(@blobref)
# 	if @blobcontent.nil?
# 		redirect '/error'
# 	end
# 	@title = @blobref
# 	erb :blob
# end

get '/node/:node_ref/edit' do
	@node = Node.get(params[:node_ref])
	if @node.nil?
		redirect '/error'
	end
	@title = 'Edit Entry'
	erb :form
end

post '/node/:node_ref/edit' do
	@node = Node.get(params[:node_ref])
	if @node.nil?
		redirect '/error'
	end
	if @node.title != params[:content]["title"]
		@node.set_title(params[:content]["title"])
	end
	if @node.content != params[:content]
		@node.set_content(params[:content])
	end
	redirect "/node/#{params[:node_ref]}"
end

# get '/node/:node_ref/:time' do
# 	@node = Node.get(params[:node_ref])
# 	if @node.nil?
# 		redirect '/error'
# 	end
# 	@revision = @node.revision(params[:time])
# 	@title = @revision.title || @node.blobref
# 	erb :node_revision
# end


# get '/chronicle' do
# 	@title = 'Timeline'
# 	@blobs = Claim.enumerate
# 	erb :chronicle_index
# end

get '/error' do
	@title = 'Error'
	erb :error
end

get '/' do
	@title = 'Micah Redding'
	@nodes = Node.enumerate
	erb :index
end


#################
# @end Routes   #
#################
