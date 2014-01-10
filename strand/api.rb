module Strand

  module API

    def camlistore
      @camlistore ||= Camlistore.new
    end

    def blobref blobcontent
      'sha1-' + Digest::SHA1.hexdigest(blobcontent)
    end

    def get blobref
      camlistore.get(blobref)
    end

    def put blobcontent
      results = camlistore.put(blobcontent)
      if !results.nil? && !results.received.nil?
        results.received.first.blobRef
      end
    end

    def describe blobref
      # at = 2012-11-02T09:35:03-00:00
      results = camlistore.describe blobref
      if !results.nil? && !results['meta'].nil? && !results['meta'][blobref].nil?
        return results['meta'][blobref]
      end
      {}
    end

    def search query
      results = camlistore.search query
      query = query.to_json if query.is_a?(Hash)
      if !results.nil? && !results['blobs'].nil?
        return results['blobs']
      end
      []
    end

    def create_permanode
      `./camput permanode`
    end

    def update_permanode blobref, attribute, value
      blobref.delete!("\n")
      attribute.delete!("\n")
      value.delete!("\n")
      `./camput attr #{blobref} #{attribute} '#{value}'`
    end

    def enumerate_type type
      search({"constraint" => {"camliType" => type}})
    end

    def find_permanode_by attribute, value
      search({
        "constraint" => {
          "camliType" => "permanode",
          "permanode" => {
            "attr" => attribute,
            "value" => value
          }
        }
      })
    end

  end

end
