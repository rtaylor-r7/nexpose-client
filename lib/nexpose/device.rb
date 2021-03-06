module Nexpose

  class Connection
    include XMLUtils

    # Find a Device by its address.
    #
    # This is a convenience method for finding a single device from a SiteDeviceListing.
    # If no site_id is provided, the first matching device will be returned when a device
    # occurs across multiple sites.
    #
    # @param [String] address Address of the device to find. Usually the IP address.
    # @param [FixNum] site_id Site ID to restrict search to.
    # @return [Device] The first matching Device with the provided address,
    #   if found.
    #
    def find_device_by_address(address, site_id = nil)
      r = execute(make_xml('SiteDeviceListingRequest', { 'site-id' => site_id }))
      if r.success
        device = REXML::XPath.first(r.res, "SiteDeviceListingResponse/SiteDevices/device[@address='#{address}']")
        return Device.new(device.attributes['id'].to_i,
                          device.attributes['address'],
                          device.parent.attributes['site-id'],
                          device.attributes['riskfactor'].to_f,
                          device.attributes['riskscore'].to_f) if device
      end
      nil
    end

    alias_method :find_asset_by_address, :find_device_by_address

    # Retrieve a list of all of the assets in a site.
    #
    # If no site-id is specified, then return all of the assets
    # for the Nexpose console, grouped by site-id.
    #
    # @param [FixNum] site_id Site ID to request device listing for. Optional.
    # @return [Array[Device]] Array of devices associated with the site, or
    #   all devices on the console if no site is provided.
    #
    def list_site_devices(site_id = nil)
      r = execute(make_xml('SiteDeviceListingRequest', { 'site-id' => site_id }))

      devices = []
      if r.success
        r.res.elements.each('SiteDeviceListingResponse/SiteDevices') do |site|
          site_id = site.attributes['site-id'].to_i
          site.elements.each('device') do |device|
            devices << Device.new(device.attributes['id'].to_i,
                                  device.attributes['address'],
                                  site_id,
                                  device.attributes['riskfactor'].to_f,
                                  device.attributes['riskscore'].to_f)
          end
        end
      end
      devices
    end

    alias_method :devices, :list_site_devices
    alias_method :list_devices, :list_site_devices
    alias_method :assets, :list_site_devices
    alias_method :list_assets, :list_site_devices

    # Get a list of all assets currently associated with a group.
    #
    # @param [Fixnum] dev_id Unique identifier of a device (asset).
    # @return [Array[Asset]] List of group assets.
    #
    def group_assets(group_id)
      payload = { 'sort' => 'assetName',
                  'table-id' => 'group-assets',
                  'groupID' => group_id }
      results = DataTable._get_json_table(self, '/data/asset/group', payload)
      results.map { |a| Asset.new(a) }
    end

    # List the vulnerability findings for a given device ID.
    #
    # @param [Fixnum] dev_id Unique identifier of a device (asset).
    # @return [Array[Vulnerability]] List of vulnerability findings.
    #
    def list_device_vulns(dev_id)
      parameters = { 'devid' => dev_id,
                     'table-id' => 'vulnerability-listing' }
      json = DataTable._get_json_table(self,
                                       '/data/vulnerability/asset-vulnerabilities',
                                       parameters)
      json.map { |vuln| VulnFinding.new(vuln) }
    end

    alias_method :list_asset_vulns, :list_device_vulns
    alias_method :asset_vulns, :list_device_vulns
    alias_method :device_vulns, :list_device_vulns

    # Retrieve a list of assets which completed in a given scan. If called
    # during a scan, this method returns currently completed assets. A
    # "completed" asset can be in one of three states: completed successfully,
    # failed due to an error, or stopped by a user.
    #
    # @param [Fixnum] scan_id Unique identifier of a scan.
    # @return [Array[CompletedAsset]] List of completed assets.
    #
    def completed_assets(scan_id)
      uri = "/data/asset/scan/#{scan_id}/complete-assets"
      AJAX.preserving_preference(self, 'scan-complete-assets') do
        data = DataTable._get_json_table(self, uri, {}, 500, nil, false)
        data.map(&CompletedAsset.method(:parse_json))
      end
    end

    def delete_device(device_id)
      r = execute(make_xml('DeviceDeleteRequest', { 'device-id' => device_id }))
      r.success
    end

    alias_method :delete_asset, :delete_device
  end

  # Object that represents a single device in a Nexpose security console.
  #
  class Device
    # A unique device ID (assigned automatically by the Nexpose console).
    attr_reader :id
    # IP Address or Hostname of this device.
    attr_reader :address
    # User assigned risk multiplier.
    attr_reader :risk_factor
    # Nexpose risk score.
    attr_reader :risk_score
    # Site ID that this device is associated with.
    attr_reader :site_id

    def initialize(id, address, site_id, risk_factor = 1.0, risk_score = 0.0)
      @id = id.to_i
      @address = address
      @site_id = site_id.to_i
      @risk_factor = risk_factor.to_f
      @risk_score = risk_score.to_f
    end
  end

  # Summary object of a completed asset for a scan.
  #
  class CompletedAsset
    # Unique identifier of an asset.
    attr_reader :id
    # IP address of the asset.
    attr_reader :ip
    # Host name of the asset, if discovered.
    attr_reader :host_name
    # Operating system fingerprint of the asset.
    attr_reader :os
    # Number of vulnerabilities discovered on the asset.
    attr_reader :vulns
    # Status of the asset on scan completion.
    # One of :completed, :error, or :stopped.
    attr_reader :status
    # Time it took to scan the asset, in milliseconds.
    attr_reader :duration

    # Internal constructor to be called by #parse_json.
    def initialize(&block)
      instance_eval(&block) if block_given?
    end

    # Convenience method for assessing "ip" as "ip_address".
    def ip_address
      ip
    end

    # Convenience method for assessing "os" as "operating_system".
    def operating_system
      os
    end

    # Internal method for converting a JSON representation into a CompletedScan
    # object.
    def self.parse_json(json)
      new do
        @id = json['id'].to_i
        @ip = json['ipAddress']
        @host_name = json['hostName']
        @os = json['operatingSystem']
        @vulns = json['vulnerabilityCount']
        @status = json['scanStatusTranslation'].downcase.to_sym
        @duration = json['duration']
      end
    end
  end
end
